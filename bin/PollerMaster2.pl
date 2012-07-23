#!/usr/bin/env perl

use strict;
use IO::Select;
use IO::Handle;
use Beanstalk::Client;
use JSON::XS;
use Getopt::Long;
use Sys::Hostname;
use POSIX;
use Data::Dumper;

# Initialise command line options
my $bsserver;
my $bsport;
my $jobTube = 'Jobs';
my $debug;

#Process commandline options
my $optsOk = GetOptions(
    'msgserver|s=s' => \$bsserver,
    'msgport|p=s'   => \$bsport,
    'jobtube|j=s'   => \$jobTube,
    'debug|d'       => \$debug,
);
die "Invalid options\n" unless $optsOk;

#Initialise other internal vars
my $pid      = $$;
my $hostname = hostname();
my $logTube  = $hostname . $pid;
my $fifo     = '/tmp/pollermaster.cmd';
my $run      = 1;
my $bsclient;
my $error;
my $children;
my %activeJobs;
my %childPids;
my %returnCodes = (
    1 => 'Successful',
    2 => 'Job data malformed',
    3 => 'Doer module returned a failure',
    4 => 'Output module returned a failure',
    5 => 'Some unknown error occured',
);

#Handles for child processes
my $jobFetchProcFh;
my $logFetchProcFh;
my $timeWatchProcFh_RDR;
my $timeWatchProcFh_WTR;
my $mainProc_RDR;
my $mainProc_WTR;

#Child PID vars
my $jfPid;
my $lfPid;
my $twPid;

#Set up signal handlers for the children processes (overwrite for the 
#main once all the children are spawned
$SIG{'TERM'} = \&childSigTermHandler;
$SIG{'INT'}  = \&childSigIntHandler;

#Create a beanstalk client object that all the children can use
#Don't connect though the child processes will have to do that for 
#themselves.
$bsclient = Beanstalk::Client->new(
    {
        server  => $bsserver,
        encoder => sub {

            #Use only a single arg that must be an array ref
            if ( ref( $_[0] ) and ref( $_[0] ) eq 'HASH' ) {
				my $data = $_[0];
				my $json = encode_json($data);
				return $json;
            }
            else {
                logging( 
	'Job data must be a HASH ref when putting on the queue');
	            return;
            }
        },
    }
);

#Fork off the required processes.
debugOut('Starting JobFetch');
if ($jfPid = open($jobFetchProcFh, "-|") ) {
	#Parent process
	$childPids{$jfPid} =1;
	$children ++;
	
	debugOut('Starting LogFetch');
	if ($lfPid = open($logFetchProcFh, "-|") ) {
		#Still the parent
		$childPids{$lfPid} =1;
		$children ++;
		
		#For the timeout watcher, we need bi-directional comms. We need
		#to send new job Ids down and read timed out IDs back
		pipe( $mainProc_RDR, $timeWatchProcFh_WTR );
		pipe( $timeWatchProcFh_RDR, $mainProc_WTR );
		
		debugOut('Starting TimeOut Monitor');
		if ( $twPid = fork ) {
			#Still the parent
			$childPids{$twPid} =1;
			$children ++;
			
			close $mainProc_RDR;
			close $mainProc_WTR;
			
			#Set up the sig handlers for the parent out of view of the
			#children.
			$SIG{'CHLD'} = \&sigChldHandler;
			$SIG{'TERM'} = \&mainSigTermHandler;
			$SIG{'INT'}  = \&mainSigIntHandler;
			
			$timeWatchProcFh_WTR->autoflush(1);
			STDOUT->autoflush(1);
			STDERR->autoflush(1);
			
			mainLineProc();
			exit;
		}
		else {
			#Job timeout monitor process
			die "Could not fork Timeout Monitor process: $!\n" unless defined $twPid;
			
			close $timeWatchProcFh_RDR;
			close $timeWatchProcFh_WTR;
			
			$mainProc_WTR->autoflush(1);
			
			timeWatchProc();
			exit;
		}
	}
	else {
		#Log fetch process
		die "Could not fork Log Fetch process: $!\n" unless defined $lfPid;
		STDOUT->autoflush(1);
		logFetchProc();
		exit;
	}
}
else {
	#Job fetch process.
	die "Could not fork Job Fetch process: $!\n" unless defined $jfPid;
	STDOUT->autoflush(1);
	jobFetchProc();
	exit;
}

sub mainLineProc {
	#Create an IO::Select obj and add the child handlers to it.
	my $select = IO::Select->new(
								 $jobFetchProcFh, 
		                         $logFetchProcFh,
		                         $timeWatchProcFh_RDR,
			                    );
	
	#Build a handle process dispatcher
	my %processDispatcher = (
	    $jobFetchProcFh      => \&processJobRet,
	    $logFetchProcFh      => \&processLogRet,
	    $timeWatchProcFh_RDR => \&processTimeRet,
    );
	
	#start an endless loop
	while ( $run ) {
		#Find childs with something for us
	    my @readyHandles = $select->can_read;	
		
		#Dispatch them.
		for my $handle (@readyHandles) {
			$processDispatcher{$handle}->($handle);
		}
		
		my @currentActive = sort {$a <=> $b} keys %activeJobs;
		debugOut("Mainline - Current active job IDs: @currentActive");
	}
	
	debugOut( 'Run has been terminated - Exiting');
    
    1;	
}

sub jobFetchProc {
	#run an endless loop
    while ($run) {
		#Check for a BS connection and connect if not connected.
		unless ($bsclient and $bsclient->socket()) {
			beanstalkConnect($bsclient, {'use' => $jobTube} );
			debugOut('Job Fetch connected to Beanstalk');
		}
		
	    my $fifoFh;	
	    my $input;
	    
		unless ( -p $fifo ) {
			if ( -e $fifo ) {
			    logging("$fifo exists as a NON fifo.  Can't continue");
			    kill 'TERM', $pid; #kill the parent
			}
			else {
				#make the fifo
				unless ( mkfifo($fifo, 0700) ) {
				    logging ('Cannot crete FIFO file');
				}
			}
		}
		
		debugOut('JobFetch - Waiting for Jobs');
   		unless ( open($fifoFh, '<', $fifo) ) {
			#check run here, we may have unblocked due to exiting
			last unless $run;
			
			logging('Could not open FIFO, cannot continue.');
	    }
	      
	    $input = <$fifoFh>;
	    close $fifoFh;
		
		$input = decode_json($input);
	    
	    unless ( ref($input) and ref($input) eq 'ARRAY'){ 
			logging('Recieved malformed data as job input');
			next;
	    };
	    
	    debugOut('JobFetch - Job batch recieved');

		JOB:
		for my $job ( @{$input} ) {
			#A single retrival can yield many jobs in an array of
			#hash refs
			next JOB if not ref($job);
			next JOB if ref($job) ne 'HASH';

            #Add the log tube to each one.
			$job->{'logsTube'} = $logTube;
			
			#See if the job has a timeout
			my $timeout = 0;
			if ( $job->{'waitTime'} ) {
				$timeout = $job->{'waitTime'} + time;
			}
			
			#Put the job on beanstalk
			my $jobObj = $bsclient->put( { 'ttr' => 30 }, $job );
			debugOut('JobFetch - Put job ID '.$jobObj->id().' to Beanstalk');
			#print to STDOUT which goes to the parent
			print $jobObj->id().":$timeout\n";
		}
		
		print "EOF\n";
	}
	
	debugOut( 'JobFetch - Run has been terminated - Exiting');
	1;
}

sub logFetchProc {
	#run an endless loop
    while ($run) {
		#Check for a BS connection and connect if not connected.
		unless ($bsclient and $bsclient->socket()) {
			beanstalkConnect($bsclient, {'watch_only' => $logTube} );
			debugOut('LogFetch connected to Beanstalk');
		}
		
		#get a log off the queue
		debugOut('LogFetch - Waiting for a log');
  
        my $log;
        eval {
			#Need to have specific sig handlers for the reserve so we can
			#stop it.
			local $SIG{'INT'}  = sub { $run = 0; die; };
			local $SIG{'TERM'} = sub { $run = 0; die; };
            $log = $bsclient->reserve(); #blocks until a job is ready
	    };
        last unless $run;
        
        debugOut('LogFetch - Received a log');

        $bsclient->delete( $log->id() );
        my $logEntry = decode_json( $log->{'data'} );

        my $worker  = $logEntry->{'worker'};
        my $jobId   = $logEntry->{'jobId'};
        my $message = $logEntry->{'message'};
        my $code    = $logEntry->{'code'};
        
        #print to STDOUT which goes to the parent
        if ( $code ) {
			print "ID $jobId: $code: $worker - $message\n";
			debugOut("LogFetch - Recieved finish code $code for $jobId");
		}
		else {
			print "ID $jobId: $worker - $message\n";
			debugOut("LogFetch - Recieved log message for $jobId");
		}
		
		print "EOF\n";
	}

	debugOut( 'LogFetch - Run has been terminated - Exiting');
	1;
}

sub timeWatchProc {
    #this process will be told about any jobs that have a timeout
	my %activeJobs;
    my $select = IO::Select->new($mainProc_RDR);
    
	#run an endless loop
    while ($run) {
		#Check for a BS connection and connect if not connected.
		unless ($bsclient and $bsclient->socket()) {
			beanstalkConnect($bsclient, {'watch_only' => $jobTube} );
			debugOut('Timeout Monitor connected to Beanstalk');
		}
		
		debugOut('Timeout Monitor - Checking for new jobs');
		for my $handle ( $select->can_read(1) ) {
			eval {
				local $SIG{'ALRM'} = sub { die; };
				alarm 2;
				
		  		while ( <$handle> ) {
					chomp;
					next if $_ eq 'EOF';
	
					my ($cmd, $id, $timeout) = split(/:/, $_);
					
					if ( $cmd eq 'ADD' ) {
						debugOut("Timeout Monitor - Adding Job $id, times out at $timeout");
					    $activeJobs{$id} = $timeout;
					}
					elsif ( $cmd eq 'DEL' ) {
						debugOut("Timeout Monitor - Deleting Job $id from tracking");
						delete $activeJobs{$id};
					}
		    
				    alarm 1;
				}
			}
		}
		
		my $stuffSentToParent;
		for my $jobId ( keys( %activeJobs ) ) {
		    
		    #See if the job has expired.
			if ( time > $activeJobs{$jobId} ) {
				#Expired, delete it
				debugOut("Timeout Monitor - Job $jobId has expired, deleting...");
				if ( $bsclient->delete( $jobId ) ) {
					delete $activeJobs{ $jobId };
				    print $mainProc_WTR "$jobId\n";
				    $stuffSentToParent ++;
				    debugOut("Timeout Monitor - Job $jobId deleted");
				}
				else {
					#Delete failed.  If because the job no longer exists
					#delete it from our records, if its because its 
					#reserved or similar, we'll deal with it next time
					#round.  Test if it exists by trying to get stats
					unless ( $bsclient->stats_job($jobId) ){
						delete $activeJobs{ $jobId };
						debugOut("Timeout Monitor - Job $jobId already gone");
					}
					else {
						debugOut("Timeout Monitor - Job $jobId not available for deletion");
					}
				}
			}
			else {
				debugOut("Timeout Monitor - Job $jobId NOT expired.");
			}
		}
		
		print "EOF\n" if $stuffSentToParent;
		
		my @currentTracked = sort {$a <=> $b} keys %activeJobs;
		debugOut("Timeout Monitor - Currently tracking these jobs for timeouts: @currentTracked");
		
		sleep 300;
	}
	
	debugOut( 'Timeout Monitor - Run has been terminated - Exiting');
	1;
}

sub processJobRet {
	my $handle = shift;

	while ( <$handle> ) {
		chomp;
		last if $_ eq 'EOF';
		
		if ( /^(\d+):(\d+)$/ ) {
			debugOut("Mainline - Got jobid $1");
    		$activeJobs{$1} = 1;
    		
    		if ($2) {  #this job has a timeout
	    		print $timeWatchProcFh_WTR "ADD:$1:$2\n";
			}
		}
		else {
			logging("Got job ID $_ from the job submitter which doesn't look right");
		}
	}
	
	debugOut('Mainline - All new jobs processed');

	1;
}

sub processLogRet {
	my $handle = shift;
	
	while ( <$handle> ) {
		chomp;
		last if $_ eq 'EOF';
		
		if ( /^ID\s(\d+):\s(\d):\s(.+)$/ ) {
			#this is a return code
			my $jobId   = $1;
			my $retCode = $2;
			my $message = $3;
			
			logging("Job $jobId finished with result: $returnCodes{$retCode}");
			delete $activeJobs{$jobId}
			  or logging("Finalising job $jobId but it is not in the active jobs list");
			print $timeWatchProcFh_WTR "DEL:$jobId\n";
		}
		else {
			#this is a generic log message
			logging($_);
		}
	}
	
	1;
}

sub processTimeRet {
	my $handle = shift;
	
	while ( <$handle> ) {
		chomp;
		last if $_ eq 'EOF';
		
		if ( /^(\d+)$/ ) {
			logging("Job $1 timed out and has been removed from the queue");
			delete $activeJobs{$1}
			  or logging("Finalising job $1 but it is not in the active jobs list");
		}
		else {
			logging("Got job ID $_ as a timedout job which doesn't look right");
		}
	}

	1;
}

sub beanstalkConnect {
	my $bsclient = shift;
	my $options  = shift;
	
	unless ( $bsclient->socket() ) {
		while ($run) {
		    #connect to beanstalk
			$bsclient->connect();
            last if $bsclient->socket();
            
            #Keep trying every 10 secs till we get a connection
		    sleep 10;
		}
	}
	
	for my $opt ( keys %{$options} ) {
		if ($opt eq 'use') {
			$bsclient->use($options->{$opt});
		}
		elsif ($opt eq 'watch') {
			$bsclient->watch($options->{$opt});
		}
		elsif ($opt eq 'watch_only') {
			$bsclient->watch_only($options->{$opt});
		}
	}

    1;		
}

sub logging {
	my $log  = shift;
	my $time = localtime();

	chomp($log);
	
	print STDERR "$time: $log\n";
	
	1;
}

sub debugOut {
	unless ($debug) { return 1; }
	
	my $message = shift;
	chomp($message);
	
	print STDERR '(DEBUG) '.localtime.": $message\n";
	
	1;
}

sub sigChldHandler {
	# Ditch dead children.
	my $pid;
	
	$pid = waitpid(-1, &WNOHANG);
	
	while ( $pid > 0 ) {
		print "Child $pid is dead. Throw it away.\n";
		delete $childPids{$pid};
		$children --;
		$pid = waitpid(-1, &WNOHANG);
    }	
	1;	
}

sub mainSigTermHandler {
	#Do the same as TERM
	mainSigIntHandler();
	1;
}

sub mainSigIntHandler {
	# Wait while the children are being murdered
	print "We need to exit.  Wait for the children to be murdered!\n";
    
    $run = 0;
    
    while ( $children ) {
		print "Waiting for children to die, $children left.\n";
		sleep;
	}
	1;
}

sub childSigTermHandler {
	#Do the same as TERM
	childSigIntHandler();
	1;
}

sub childSigIntHandler {
	# Wait while the children are being murdered
    $run = 0;
    1;
}
