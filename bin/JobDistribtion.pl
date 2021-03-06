#!/usr/bin/env perl

=head1 NAME

  PollerMaster.pl

=head1 USAGE

  PollerMaster.pl -c <config file> [-d]

      -c|--cfgfile : Full path to configuration file
      -d|--daemon  : Daemonize the process.

=head1 DESCRIPTION

  Poller Master listens on a FIFO for JSON formatted job specifications
  and submits them to Beanstalkd for processing by a worker.  It also
  sets up a return 'tube' on Beanstalkd on which it expects to receive
  any log messages as well as a result code for jobs as they are
  completed.

  Submitted jobs are tracked until completion.  Jobs are regarded as
  completeted when either a result code for the job is received or the
  job has been on the queue for longer than the timeout at which point
  PollerMaster will cancel it.  This protects the overall system from
  a situation where the Master is receiving and queuing them when no
  workers are active and servicing the queue.  Without cancelling the
  jobs, they will stay in the queue indefinately and when a worker comes
  online, it will run through all the jobs as fast as possible even
  though many of the jobs would no longer be relevant.

  The timeout, if required, should be specified using the 'waitTime' key
  on the job data.

=head1 JOB FORMAT

  Jobs can be submitted in batches and should be submitted to the master
  as a JSON string via the FIFO. Its structure is as follows:

  $jobs = [
      {
		  'process'  => <processor module>,
		  'output'   => <output module>,
		  'waitTime' => <no of secconds job can be queued>,
		  'processOptions => {
		      <hash of options required by the process module>
		  },
		  'outputOptions' => {
			  <hash of options required by the output module>
		  }
      },
      @more_hash_refs,
  ];

  The 'process' key is really the only mandatory key.  Without this key,
  no logic can be employed to actually do any work.

  The 'output' key can be used to specify a module that will actually
  'do' something with the results of the process. This isn't mandatory
  because, potentially the process may not produce any data or
  potentially the process can actually do any outputting itself.  Using
  an output module however allows the same process to be run with
  different output modules so that you can direct output in a way that
  is appropriate for various environments without having to mess with
  the process logic.

  The 'processOptions' and 'outputOptions' keys should contain hashes of
  options pertaining to the 'process' and 'output' modules respectively.
  Please see the documentation of the modules you are using for an idea
  of what is appropriate here.

=cut

use strict;
use lib '../lib';
use File::Pid;
use IO::Select;
use IO::Handle;
use Beanstalk::Client;
use JSON::XS;
use Getopt::Long;
use Sys::Hostname;
use POSIX;
use Log::Dispatch::Config;
use Config::Auto;
use Data::Dumper;

# Initialise command line options
my $cfgfile;
my $daemon;

#Process commandline options
my $optsOk = GetOptions(
    'cfgfile|c=s'   => \$cfgfile,
    'daemon|d'      => \$daemon,
)
  or die "Invalid options\n";

#Setup logging
Log::Dispatch::Config->configure($cfgfile);
my $logger = Log::Dispatch::Config->instance;
$logger->{'outputs'}->{'syslog'}->{'ident'} = 'JobDispatch';

#Set up signal handlers for the children processes (overwrite for the
#main once all the children are spawned where needed
$SIG{'TERM'}    = \&childSigTermHandler;
$SIG{'INT'}     = \&childSigIntHandler;
$SIG{ __DIE__ } = \&dieHandle;

#Daemonize if appropriate
my $pidfile;
if ($daemon) {
	daemonize();
}

$logger->notice('POLLER MASTER STARTING UP');

unless ($optsOk and $cfgfile and -f $cfgfile) {
    $logger->critical('Invalid options. Must supply -c <config file> with valid file');
    exit;
}

#Load config
my $config   = getConfig($cfgfile);
my $fifo     = $config->{'MASTER_FIFO'};
my $bsserver = $config->{'BS_SERVER'};
my $bsport   = $config->{'BS_PORT'};
my $jobTube  = $config->{'BS_JOBQ'};

unless ( $fifo and $bsserver and $bsport and $jobTube ){
	$logger->critical('Options missing from config file.  Must include: MASTER_FIFO, BS_SERVER, BS_PORT, BS_JOBQ');
	exit;
}

#Initialise other internal vars
my $pid      = $$;
my $hostname = hostname();
my $logTube  = $hostname . $pid;
my $run      = 1;
my $bsclient;
my $error;
my $children;
my %activeJobs;
my %childPids;
my %returnCodes = (
    1 => 'Successful.',
    2 => 'Job data malformed.',
    3 => 'A module in the process does not exist.',
    4 => 'A process module did not return a result.',
    5 => 'A process module died.',
);

$logger->notice('Logs tube is '.$logTube);

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
                $logger->info(
	'Job data must be a HASH ref when putting on the queue');
	            return;
            }
        },
    }
);

#Fork off the required processes.
$logger->notice('INIT - Starting JobFetch');
if ($jfPid = open($jobFetchProcFh, "-|") ) {
	#Parent process
	$childPids{$jfPid} =1;
	$children ++;

	$logger->notice('INIT - Starting LogFetch');
	if ($lfPid = open($logFetchProcFh, "-|") ) {
		#Still the parent
		$childPids{$lfPid} =1;
		$children ++;

		#For the timeout watcher, we need bi-directional comms. We need
		#to send new job Ids down and read timed out IDs back
		pipe( $mainProc_RDR, $timeWatchProcFh_WTR );
		pipe( $timeWatchProcFh_RDR, $mainProc_WTR );

		$logger->notice('INIT - Starting TimeOut Monitor');
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

			$pidfile->remove if $daemon;
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
		$logger->debug("Mainline - Current active job IDs: @currentActive");
	}

	$logger->notice( 'Run has been terminated - Exiting');

    1;
}

sub jobFetchProc {
	#run an endless loop
    while ($run) {

	    my $fifoFh;
	    my $input;

		unless ( -p $fifo ) {
			if ( -e $fifo ) {
			    $logger->emerg("$fifo exists as a NON fifo.  Can't continue");
			    kill 'TERM', $pid; #kill the parent
			}
			else {
				#make the fifo
				unless ( mkfifo($fifo, 0700) ) {
				    $logger->emerg('Cannot crete FIFO file');
				}
			}
		}

		$logger->info('JobFetch - Waiting for Jobs');
   		unless ( open($fifoFh, '<', $fifo) ) {
			#check run here, we may have unblocked due to exiting
			last unless $run;

			$logger->info('Could not open FIFO, cannot continue.');
	    }

	    $input = <$fifoFh>;
	    close $fifoFh;
		
        eval {
            $input = decode_json($input);
            1;
        };
	    
	    unless ( ref($input) and ref($input) eq 'ARRAY'){ 
			$logger->error('JobFetch - Recieved malformed data as job input');
            if ($@) {
                $logger->error($@);
            }
			next;
	    };

	    $logger->info('JobFetch - Job batch recieved');

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

			#See if the job has a priority
			my $priority = 10;
			if ( $job->{'priority'} ) {
				$priority = $job->{'priority'};
			}

    		#Check for a BS connection and connect if not connected.
			unless ($bsclient and $bsclient->socket()) {
				beanstalkConnect($bsclient, {'use' => $jobTube} );
				$logger->info('Job Fetch connected to Beanstalk');
			}

			#Put the job on beanstalk
			my $jobObj = $bsclient->put(
			    {
				  'ttr'      => 120,
			      'priority' => $priority,
			    },
			    $job
		    );

			unless ($jobObj) {
				$logger->critical('Could not put job on Beanstalk queue');
				next JOB;
			}

			$logger->info('JobFetch - Put job ID '.$jobObj->id().' to Beanstalk');
			#print to STDOUT which goes to the parent
			print $jobObj->id().":$timeout\n";
		}

		print "EOF\n";
	}

	$logger->notice( 'JobFetch - Run has been terminated - Exiting');
	1;
}

sub logFetchProc {
	#run an endless loop
    while ($run) {
		#Check for a BS connection and connect if not connected.
		unless ($bsclient and $bsclient->socket()) {
			beanstalkConnect($bsclient, {'watch_only' => $logTube} );
			$logger->info('LogFetch connected to Beanstalk');
		}

		#get a log off the queue
		$logger->debug('LogFetch - Waiting for a log');

        my $log;
        eval {
			#Need to have specific sig handlers for the reserve so we can
			#stop it.
			local $SIG{'INT'}  = sub { $run = 0; die; };
			local $SIG{'TERM'} = sub { $run = 0; die; };
            $log = $bsclient->reserve(); #blocks until a job is ready
	    };
        last unless $run;
        next unless $log;

        $logger->debug('LogFetch - Received a log');

        $bsclient->delete( $log->id() );
        my $logEntry = decode_json( $log->{'data'} );

        my $worker  = $logEntry->{'worker'};
        my $jobId   = $logEntry->{'jobId'};
        my $message = $logEntry->{'message'};
        my $code    = $logEntry->{'code'};

        #print to STDOUT which goes to the parent
        if ( $code ) {
			print "Job $jobId: $code: $worker - $message\n";
			$logger->debug("LogFetch - Recieved finish code $code for $jobId");
		}
		else {
			print "Job $jobId: $worker - $message\n";
			$logger->debug("LogFetch - Recieved log message for $jobId");
		}

		print "EOF\n";
	}

	$logger->notice( 'LogFetch - Run has been terminated - Exiting');
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
			$logger->info('Timeout Monitor connected to Beanstalk');
		}

		$logger->debug('Timeout Monitor - Checking for new jobs');
		for my $handle ( $select->can_read(1) ) {
			eval {
				local $SIG{'ALRM'}  = sub { die; };
				alarm 2;

		  		while ( <$handle> ) {
					chomp;
					next if $_ eq 'EOF';

					my ($cmd, $id, $timeout) = split(/:/, $_);

					if ( $cmd eq 'ADD' ) {
						$logger->debug("Timeout Monitor - Adding Job $id, times out at $timeout");
					    $activeJobs{$id} = $timeout;
					}
					elsif ( $cmd eq 'DEL' ) {
						$logger->debug("Timeout Monitor - Deleting Job $id from tracking");
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
				$logger->warning("Timeout Monitor - Job $jobId has expired, deleting...");

				if ( $bsclient->delete( $jobId ) ) {
					delete $activeJobs{ $jobId };
				    print $mainProc_WTR "$jobId\n";
				    $stuffSentToParent ++;
				    $logger->debug("Timeout Monitor - Job $jobId deleted");
				}
				else {
					#Delete failed.  If because the job no longer exists
					#delete it from our records, if its because its
					#reserved or similar, we'll deal with it next time
					#round.  Test if it exists by trying to get stats

					unless ( $bsclient->stats_job($jobId) ){
						delete $activeJobs{ $jobId };
						$logger->debug("Timeout Monitor - Job $jobId already gone");
					}
					else {
						$logger->debug("Timeout Monitor - Job $jobId not available for deletion");
					}
				}
			}
			else {
				$logger->debug("Timeout Monitor - Job $jobId NOT expired.");
			}
		}

		print "EOF\n" if $stuffSentToParent;

		my @currentTracked = sort {$a <=> $b} keys %activeJobs;
		$logger->debug("Timeout Monitor - Currently tracking these jobs for timeouts: @currentTracked");

		sleep 300;
	}

	$logger->notice( 'Timeout Monitor - Run has been terminated - Exiting');
	1;
}

sub processJobRet {
	my $handle = shift;

	while ( <$handle> ) {
		chomp;
		last if $_ eq 'EOF';

		if ( /^(\d+):(\d+)$/ ) {
			$logger->debug("Mainline - Got jobid $1");
    		$activeJobs{$1} = 1;

    		if ($2) {  #this job has a timeout
	    		print $timeWatchProcFh_WTR "ADD:$1:$2\n";
			}
		}
		else {
			$logger->error("Got job ID $_ from the job submitter which doesn't look right");
		}
	}

	$logger->debug('Mainline - All new jobs processed');

	1;
}

sub processLogRet {
	my $handle = shift;

	while ( <$handle> ) {
		chomp;
		last if $_ eq 'EOF';

		if ( /^Job\s(\d+):\s(\d):\s(.+)$/ ) {
			#this is a return code
			my $jobId   = $1;
			my $retCode = $2;
			my $message = $3;

			if ($retCode > 1 ) {
				$logger->error("Job $jobId finished with result: $returnCodes{$retCode}");
			}
			else {
				$logger->info("Job $jobId finished with result: $returnCodes{$retCode}");
			}
			delete $activeJobs{$jobId}
			  or $logger->warn("Finalising job $jobId but it is not in the active jobs list");
			print $timeWatchProcFh_WTR "DEL:$jobId\n";
		}
		else {
			#this is a generic log message.  Use warn. If its not a
			#successfull job competetion which is handled above, any
			#other log message is probably dubious.
			$logger->warn($_);
		}
	}

	1;
}

sub processTimeRet {
	my $handle = shift;

	while ( <$handle> ) {
		chomp;
		last if $_ eq 'EOF';

		if ( m/^(\d+)$/ ) {
			$logger->info("Job $1 timed out and has been removed from the queue");
			delete $activeJobs{$1}
			  or $logger->info("Finalising job $1 but it is not in the active jobs list");
		}
		else {
			$logger->error("Got job ID $_ as a timedout job which doesn't look right");
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

            $logger->warning('Could not connect to Beanstalk.  Will retry in 30 secs');
            #Keep trying every 30 secs till we get a connection
		    sleep 30;
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
		else {
			$logger->warning("Invalid option $opt supplied for Beanstalk connection");
		}
	}

    1;
}

sub sigChldHandler {
	# Ditch dead children.
	my $pid;

	$pid = waitpid(-1, &WNOHANG);

	while ( $pid > 0 ) {
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
	$logger->notice('SHUTTING DOWN!');

    $run = 0;
    kill 'INT', keys %childPids;

    while ( $children ) {
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

sub dieHandle {
	die @_ if $^S; #Dont do anything special in an eval
	$logger->critical(@_);
	return 1;
}

sub daemonize {
	POSIX::setsid or die "setsid: $!";
	my $pid = fork ();

	if ($pid < 0) {
		die "fork: $!";
	} elsif ($pid) {
		#Parent process exits leaving the daemonized process to run.
		exit 0;
	}

	chdir '/';
	umask 0;

	open (STDIN,  '<','/dev/null');
	open (STDOUT, '>','/dev/null');
	open (STDERR, '>&STDOUT'  );

	# Check if this process is already running, Don't run twice!
	my ($thisFile) = $0 =~ m|([^/]+)$|;
	$pidfile = File::Pid->new({ 'file' => "/var/tmp/$thisFile.pid" });
	die "Process is already running\n" if $pidfile->running;
	$pidfile->write or die "Could not create pidfile: $!\n";


	1;
}

sub getConfig {
    my $file = shift;
    return unless ( $file and -f $file );
    my $config = Config::Auto::parse($file);
    return $config;
}
