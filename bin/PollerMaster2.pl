#!/usr/bin/env perl

use strict;
use IO::Select;
use Beanstalk::Client;
use JSON::XS;
use Getopt::Long;
use Sys::Hostname;
use POSIX qw(mkfifo);
use Data::Dumper;

# Initialise command line options
my $bsserver;
my $bsport;
my $jobTube;
my $verbose;

#Process commandline options
my $optsOk = GetOptions(
    'msgserver|s=s' => \$bsserver,
    'msgport|p=s'   => \$bsport,
    'jobtube|j=s'   => \$jobTube,
    'verbose|v'     => \$verbose,
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
my $timeWatchProcFh;

#Child PID vars
my $jfPid;
my $lfPid;
my $twPid;

#Set up signal handlers
$SIG{'CHLD'} = \&sigChldHandler;
$SIG{'TERM'} = \&sigTermHandler;
$SIG{'INT'}  = \&sigIntHandler;

#Create a beanstalk client object that all the children can use
#Don't connect though the child processes will have to do that for 
#themselves.
$bsclient = Beanstalk::Client->new(
    {
        server  => $bsserver,
        encoder => sub {

            #Use only a single arg that must be an array ref
            if ( ref( $_[0] and ref( $_[0] ) eq 'HASH') ) {
				my $data = $_[0];
				my $json = encode_json($data);
				return $json;
            }
            else {
                die 
	"Job data must be a HASH ref when putting on the queue\n";
            }
        },
    }
);

#Fork off the required processes.
if ($jfPid = open($jobFetchProcFh, "-|") ) {
	#Parent process
	$childPids{$jfPid} =1;
	$children ++;
	
	if ($lfPid = open($logFetchProcFh, "-|") ) {
		#Still the parent
		$childPids{$lfPid} =1;
		$children ++;
		
		if ($twPid = open($timeWatchProcFh, "-|") ) {
			#Still the parent
			$childPids{$twPid} =1;
			$children ++;
			
			mainLineProc();
		}
		else {
			#Job timeout monitor process
			die "Could not fork process: $!\n" unless $lfPid;
			$| ++;
			timeWatchProc();
			exit;
		}
	}
	else {
		#Log fetch process
		die "Could not fork process: $!\n" unless $lfPid;
		$| ++;
		logFetchProc();
		exit;
	}
}
else {
	#Job fetch process.
	die "Could not fork process: $!\n" unless $jfPid;
	$| ++;
	jobFetchProc();
	exit;
}

sub mainLineProc {
	#Create an IO::Select obj and add the child handlers to it.
	my $select = IO::Select->new([
								 $jobFetchProcFh, 
		                         $logFetchProcFh,
		                         $timeWatchProcFh,
			                    ]);
	
	#Build a handle process dispatcher
	my %processDispatcher = (
	    $jobFetchProcFh  => \&processJobRet,
	    $logFetchProcFh  => \&processLogRet,
	    $timeWatchProcFh => \&processTimeRet,
    );
	
	#start an endless loop
	while ( $run ) {
		#Find childs with something for us
	    my @readyHandles = $select->can_read();	
		
		#Dispatch them.
		for my $handle (@readyHandles) {
			$processDispatcher{$handle}->($handle);
		}
	}
    
    1;	
}

sub jobFetchProc {
	#run an endless loop
    while ($run) {
		#Check for a BS connection and connect if not connected.
		unless ($bsclient and $bsclient->socket()) {
			beanstalkConnect($bsclient, {'use' => $jobTube} );
		}
		
	    my $fifoFh;	
	    my $input;
		unless ( -p $fifo ) {
			if ( -e $fifo ) {
			    logging("$fifo exists as a NON fifo.  Can't continue");
			    kill 'INT', $pid; #kill the parent
			}
			else {
				#make the fifo
				unless ( mkfifo($fifo, 0700) ) {
				    logging ('Cannot crete FIFO file');
				    kill 'INT', $pid; #kill the parent
				}
			}
		}
		
   		unless ( open($fifoFh, '<', $fifo) ) {
			logging('Could not open FIFO, cannot continue.');
			kill 'INT', $pid; #kill the parent
	    }
	      
	    $input = <$fifoFh>;
	    close $fifoFh;
		
		$input = decode_json($input);
	    
	    unless ( ref($input) and ref($input) eq 'ARRAY'){ 
			logging('Recieved malformed data as job input');
			next;
	    };

		JOB:
		for my $job ( @{$input} ) {
			#A single retrival can yield many jobs in an array of
			#hash refs
			next JOB if not ref($job);
			next JOB if ref($job) ne 'HASH';

            #Add the log tube to each one.
			$job->{'logsTube'} = $logTube;
			
			#Put the job on beanstalk
			my $jobObj = $bsclient->put( { 'ttr' => 30 }, $job );
			
			#print to STDOUT which goes to the parent
			print $jobObj->id()."\n";
		}
	}
	
	1;
}

sub logFetchProc {
	#run an endless loop
    while ($run) {
		#Check for a BS connection and connect if not connected.
		unless ($bsclient and $bsclient->socket()) {
			beanstalkConnect($bsclient, {'watch_only' => $logTube} );
		}
		
		#get a log off the queue
        my $log = $bsclient->reserve(); #blocks until a job is ready
        $bsclient->delete( $log->id() );
        my $logEntry = decode_json( $log->{'data'} );

        my $worker  = $logEntry->{'worker'};
        my $jobId   = $logEntry->{'jobId'};
        my $message = $logEntry->{'message'};
        my $code    = $logEntry->{'code'};
        
        #print to STDOUT which goes to the parent
        if ( $code ) {
			print "ID $jobId: $code: $worker - $message\n";
		}
		else {
			print "ID $jobId: $worker - $message\n";
		}
	}
}

sub timeWatchProc {
	#run an endless loop
    while ($run) {
		#Check for a BS connection and connect if not connected.
		unless ($bsclient and $bsclient->socket()) {
			beanstalkConnect($bsclient, {'watch_only' => $jobTube} );
		}
		
		my $noOfReady = $bsclient->stats_tube($jobTube)->current_jobs_ready();
		
		for ( 1..$noOfReady ) {
			
			#get a log off the queue
	        my $job = $bsclient->reserve(); #blocks until a job is ready
	        my $id  = $job->id();
		    my $jobData = decode_json($job);
		    
		    #See if there is a timeout and if it has expired.
		    if ( $jobData->{'timeSubmitted'} and $readyTimeout ) {
				my $timeout = $jobData->{'timeSubmitted'} + $readyTimeout;
				
				if ( $timeout > time() ) {
					#Expired, delete it
					$bsclient->delete( $id );
					print "$id\n";
				}
			}
			else {
				#Not expired.
				$bsclient->release( $id );
			}
		}
		
		sleep 300;
	}
	
	1;
}

sub processJobRet {
	my $handle = shift;
	
	while ( <$handle> ) {
		if ( $_ =~ /^(\d+)$/ ) {
    		$activeJobs{$_} = 1;
		}
		else {
			logging("Got job ID $_ from the job submitter which doesn't look right");
		}
	}

	1;
}

sub processLogRet {
	my $handle = shift;
	
	while ( <$handle> ) {
		if ( $_ =~ /^ID\s(\d+):\s(\d):\s(.+)$/ ) {
			#this is a return code
			my $jobId   = $1;
			my $retCode = $2;
			my $message = $3;
			
			logging("Job $jobId finished with result: $returnCodes{$retCode}");
			delete $activeJobs{$2}
			  or logging("Finalising job $jobId but it is not in the active jobs list");
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
		if ( $_ =~ /^(\d+)$/ ) {
			logging("Job $1 timed out and has been removed from the queue");
			delete $activeJobs{$1}
			  or logging("Finalising job $1 but it is not in the active jobs list");
		}
		else {
			logging("Got job ID $_ as a timedout job which doesn't look right");
		}
	}
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
	
	print "$time: $log\n";
	
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

sub sigTermHandler {
	# Wait while the children are being murdered
	print "We need to exit.  Wait for the children to be murdered!\n";

    while ( $children ) {
		print "Waiting for children to die, $children left.\n";
		sleep;
	}

	exit;	
}

sub sigIntHandler {
	#Do the same as TERM
	sigTermHandler();
}
