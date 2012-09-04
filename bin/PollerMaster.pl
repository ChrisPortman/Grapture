#!/usr/bin/env perl
# $Id: PollerMaster.pl,v 1.13 2012/06/18 02:57:37 cportman Exp $

=head1 NAME

  PollerMaster.pl

=head1 SYNOPSIS

  PollerMaster.pl -s <beanstalk_server> -p <beanstalk_port> -i <input_module> [-f <input_file>]

=head1 DESCRIPTION

  Harvests parameters for work to be done formats it and presents it for
  processing via a Beanstalk job queue.

  It is expected that PollerWorker.pl will be running in one or more
  locations to recieve the jobs, process them and submit the results
  back via Beanstalk.

  For the purpose of this process, a 'job' is a collection of similar
  tasks for a single target.  Eg, multiple SNMP retrievals for 'targetA'
  would be bundled into one job.  A command to be executed over SSH on
  'targetA' would go in a seperate job.

=cut

use strict;
use warnings;

use Beanstalk::Client;
use JSON::XS;
use Getopt::Long;
use Data::Dumper;
use threads;
use Sys::Hostname;
use POSIX qw(mkfifo);

logging('Poller Master starting up');

#setup some variables

#cmd line vars
my $file;
my $bsserver;
my $bsport;
my $bsclient;
my $jobTube = 'Jobs';
my $verbose;
my $target;
my $module;
my @args;
my $input  = 'stdin';
my $output = 'stdout';

#internal vars
my $error;
my %activeJobs;
my $logThread;
my $resultsTube;
my $logsTube;
my $pid      = $$;
my $hostname = hostname();

#---------------------#
#        SETUP        #
#---------------------#

#Process commandline options
my $optsOk = GetOptions(
    'msgserver|s=s' => \$bsserver,
    'msgport|p=s'   => \$bsport,
    'jobtube|j=s'   => \$jobTube,
    'file|f=s'      => \$file,
    'input|i=s'     => \$input,
    'output|o=s'    => \$output,
    'target|t=s'    => \$target,
    'module|m=s'    => \$module,
    'args|a=s{,}'   => \@args,
    'verbose|v'     => \$verbose,
);
die "Invalid options\n" unless $optsOk;

#TODO: Usage.

local $SIG{INT} = sub {
    $logThread->kill('KILL')->detach()
      if $logThread;

    exit 0;
};

#setup the callback tube names
$resultsTube = 'results-' . $hostname . $pid;
$logsTube    = 'logs-' . $hostname . $pid;

#Start up a log monitor thread

$logThread = threads->create( \&logMonitor );

#---------------------#
#    COMPILE JOBS     #
#---------------------#

#module dispatcher to use to aquire job details.
my %inputModules = (
    'stdin' => \&standardInput,
    'fifo'  => \&fifoIn,
);

my $run = 1;
while ($run) {
    my $jobParams;
    my $submittedJobs;
    my $completedJobs;
    my $erroredJobs;

    #Connect to the beanstalk server.
    unless ( $bsclient and $bsclient->socket() ) {

        $bsclient = undef;

        logging('Connecting to Beanstalk...');

        until ($bsclient) {
            $bsclient = beanstalkConnect();
            last if $bsclient;
            sleep 10;
        }

        #Put jobs onto the 'jobs' tube, watch for results on the 'results' tube.
        $bsclient->use( lc($jobTube) );
        $bsclient->watch_only( ($resultsTube) );

        logging('Connected to Beanstalk.');
    }

    logging('Ready for input...');

    #Use a sub from the dispatcher.
    if ( $inputModules{$input} ) {
        $jobParams = $inputModules{$input}->($file);
        if ( not ref($jobParams) or ref($jobParams) ne 'ARRAY' ) {
            die "couldnt build a valid data set to build jobs from\n";
        }
    }
    else {
        die "Invalid input module specified\n";
    }

    #---------------------#
    #      RUN JOBS       #
    #---------------------#

  TARGET:

    #iterate through each target in the jobs data structure
    for my $job ( @{$jobParams} ) {

        #submit the job to the queue
        my $jobId = $bsclient->put( { 'ttr' => 30 }, $job );
        $submittedJobs++;

        #~ if ( $error = $bsclient->error() ) {
        #~ error("ERROR: Job submission failed: $error");
        #~ $error = undef;
        #~ $erroredJobs++;
        #~ next;
        #~ }

        $activeJobs{ $jobId->{id} } = 'Submitted';
    }

  ACTIVEJOB:

    #While there are active jobs
    while ( keys %activeJobs ) {

        #Iterate over each currently active job and update its status
        for my $job ( keys %activeJobs ) {

            #get the stats
            my $statusObj = $bsclient->stats_job($job);

            #If the status object comes back, the job is still in the queue
            if ($statusObj) {
                my $state = $statusObj->state();
                if ( $activeJobs{$job} ne $state ) {
                    $activeJobs{$job} = $state;
                    debug("Job ID $job state is $state");
                }

            }
            else {
                my $state = 'Finished';
                if ( $activeJobs{$job} ne $state ) {
                    $activeJobs{$job} = $state;
                    debug("Job ID $job state is $state, result pending.");
                }
            }
        }

      RESULT:

        #Harvest any results.  This loop will keep looping as long as we
        #get results, as soon as there are no more results, break out to the
        #outer loop.
        while (1) {

            #Get a result 'job' but dont block, if theres nothing, move on.
            my $result = $bsclient->reserve( [1] );

            if ($result) {

                #Yay a result
                my $resultId   = $result->{'id'};
                my $resultData = decode_json( $result->{'data'} );

                print "Processing result for job $resultData->{'id'}\n";

                #Dispatch to output module
                my %outputModules = ( 'stdout' => \&standardOutput, );

                if ( $resultData->{'result'} ) {
                    if ( $outputModules{$output} ) {
                        $outputModules{$output}
                          ->( $resultData->{'target'}, $resultData->{'result'} )
                          or error("WARNING: Output module failed");
                    }
                    else {
                        error(
                            "WARNING no output module $output, assuming STDOUT"
                        );
                        $outputModules{'stdout'}->( $resultData->{'result'} )
                          or error("WARNING: Output module failed");
                    }
                    $completedJobs++;
                }
                else {
                    error("Job ID $resultData->{'id'} failed");
                    $erroredJobs++;
                }

                #Delete the job from the active jobs so that the outer loop
                #will eventually exit once there are no more active jobs to
                #wait on.
                delete $activeJobs{ $resultData->{'id'} };

                #remove the result from the queue
                $bsclient->delete($resultId)
                  or warn "Job delete failed\n";
            }
            else {

                #we didnt get a result, there may be no more results to come
                #break out to the outer loop which will see.
                last RESULT;
            }
        }

        #sleep 2;

    }

    #---------------------#
    #     FINISH UP       #
    #---------------------#

    #Print a report.
    debug( 'Jobs submitted: ' . ( $submittedJobs || '0' ) );
    debug( 'Jobs completed: ' . ( $completedJobs || '0' ) );
    debug( '  Jobs errored: ' . ( $erroredJobs   || '0' ) );
    print "\n";

}

$logThread->kill('KILL')->detach()
  if $logThread;

$bsclient->quit();

exit 0;

#---------------------#
#    SUB ROUTINES     #
#---------------------#

=head2 fileInput

=head3 SYNOPSIS

  fileInput($filename)

head3 DESCRIPTION

  Opens the file in I<$file> and parses the contents into an array of
  array references.

  The file should contain one line of comma separated values per task.
  The values and the required order depend on the module to be run by
  the worker.  See the perldoc for PollerWorker.pl for the possible
  modules and the data requrements for each. However the first value
  must be the target the task should be run against and the second should
  be the name of the tasks module.

=cut

sub fileInput {
    my $inputFile = shift;
    return unless $inputFile;

    my @fileContents;

    #Open the file
    open( my $fh, '<', $inputFile )
      or return;
    my @fileLines = <$fh>;
    close $fh
      or error( 'Unable to CLOSE ' . $inputFile );

  LINES:

    #suck in the contents of the file.
    for my $line (@fileLines) {
        chomp($line);

        next if $line =~ m/^\s*$/smx;    #ignore empty lines
        next if $line =~ m/^\s*#/smx;    #ignore comment lines

        #line should look like:
        #<target>, <module>, <arg> [{,<arg>}]
        my @lineVals = split( /\s*,\s*/smx, $line );

        push @fileContents, \@lineVals;
    }

    #Send the data to buildJobs and get back a structure that can be
    #used to actually create the jobs.
    return buildJobs( \@fileContents );
}

=head2 standardInput

=head3 SYNOPSIS

  standardInput();

head3 DESCRIPTION

  Reads Job parameter input from STDIN.  This enables a simple module of
  invoking this program from others by simply doing something like:

  $results = `echo $input | PollerMaster.pl ...`;

  Which will pipe the output of 'echo $input' (where $input contains
  appropriately formated text) into PollerMaster.pl via STDIN.

=cut

sub standardInput {
    my @jobParams;
    my $input = <>;

    $input = decode_json($input);

    unless ( ref($input) and ref($input) eq 'ARRAY' ) { return; }

    return buildJobs($input);

    #~ INPUT:
    #~ while ( my $line = <> ) {
    #~ chomp($line);
    #~ if ( $line =~ m/^\s*end\s*$/smxi ) {
    #~ last INPUT;
    #~ }
    #~ else {
    #~ my @lineVals = split( /\s*,\s*/smx, $line );
    #~ push @jobParams, \@lineVals;
    #~ }
    #~ }

}

sub fifoIn {
    my @jobParams;
    my $fifo = '/tmp/pollermaster.cmd';
    my $fifoFH;
    my $input;

    if ( -p $fifo ) {

        #open the fifo
        open( $fifoFH, '<', $fifo )
          or die "Could not open FIFO, can't continue.\n";

        $input = <$fifoFH>;
        close $fifoFH;
    }
    elsif ( -e $fifo ) {
        die "$fifo exists as a NON fifo.  Can't continue\n";
    }
    else {
        #make the fifo and open it
        mkfifo( $fifo, 0700 )
          or die "Cannot crete FIFO file\n";

        open( $fifoFH, '<', $fifo )
          or die "Could not open FIFO, can't continue.\n";

        $input = <$fifoFH>;
        close $fifoFH;
    }

    $input = decode_json($input);

    unless ( ref($input) and ref($input) eq 'ARRAY' ) { return; }

    return buildJobs($input);

}

=head2 standardOutput

=head3 SYNOPSIS

  standardOutput($target, $data);

head3 DESCRIPTION

  Prints the results to STDOUT in the form of a JSON encoded string.

=cut

sub standardOutput {
    my $target = shift;
    my $data   = shift;

    if ( ref($data) ) {
        my $result = { 'result' => $data };

        #debug( Dumper($result) );
    }
    else {
        #print encode_json( [$data] ) . "\n";
    }
    return 1;
}

sub pipeOutput {

    return 1;
}

=head2 buildJobs

=head3 SYNOPSIS

  buildJobs( $arrayref );

=head3 DESCRIPTION

  Accepts an array ref that should be compiled by an input specific
  module and churns it into a consistant data structure that can be used
  to create jobs in the beanstalk queues.

  $arrayref is a data structure that looks like:

  $VAR1 = [
      [ <target> , <module> , @module_args ],
      [ <target> , <module> , @module_args ],
      ...
  ],

  Returns a data structure that looks like:

  $VAR1 = {
      '<target>' => {
          '<module>' => [
              { 'target'   => '<target>',
                'module' => '<module>',
                'args'   => [ qw( remaining file line ) ],
              },
              { 'target'   => '<target>',
                'module' => '<module>',
                'args'   => [ qw( remaining file line ) ],
              },
              ...,
          ],
             '<module>' => [
              { 'target'   => '<target>',
                'module' => '<module>',
                'args'   => [ qw( remaining file line ) ],
              },
                 { 'target'   => '<target>',
                'module' => '<module>',
                'args'   => [ qw( remaining file line ) ],
              },
              ...,
          ],
          ...,
      },
      ...,
  }

=cut

sub buildJobs {
    my $data = shift;

    #insist on a single array ref
    if ( ref $data eq 'ARRAY' ) {

      DATALINE:
        for my $line ( @{$data} ) {

            #each item in the data array mush be an array ref
            next DATALINE if not ref($line);
            next DATALINE if ref($line) ne 'HASH';

            $line->{'resultsTube'} = $resultsTube;
            $line->{'logsTube'}    = $logsTube;

        }
    }
    else {
        return;
    }
    return wantarray ? @{$data} : $data;
}

=head2 logMonitor

=head3 SYNOPSIS

  should be run as a thread:
  $thread = threads->create('logMonitor');

=head3 DESCRIPTION

  Subscribes to the 'logging' tube on the Beanstalk server.  Workers can
  log through this tube back to the master.

=cut

sub logMonitor {

    local $SIG{'KILL'} = sub {
        $bsclient->quit() if $bsclient->socket();
        threads->exit();
    };

    #~ $bsclient->connect();
    #~ if ( not $bsclient->socket() ) {
    #~ $error = $bsclient->error() || '';
    #~ error("Logging thread could not connect: $error");
    #~ threads->detach();
    #~ return;
    #~ }
    $bsclient = beanstalkConnect();

    $bsclient->watch_only( ($logsTube) );

    logging('Logging thread initialised.');

    while (1) {
        my $log      = $bsclient->reserve();
        my $logEntry = decode_json( $log->{'data'} );

        my $worker  = $logEntry->{'worker'};
        my $jobId   = $logEntry->{'jobId'};
        my $time    = $logEntry->{'time'};
        my $message = $logEntry->{'message'};

        logging("$time - $worker/$jobId: $message")
          if ( $worker and $time and $message and $jobId );

        $bsclient->delete( $log->{'id'} );
    }

    $bsclient->quit();
    threads->detach();
    return 1;
}

sub beanstalkConnect {
    my $bsclient = Beanstalk::Client->new(
        {
            server  => $bsserver,
            encoder => sub {

                #Use only a single arg that must be an array ref
                if ( ref( $_[0] ) ) {
                    if ( ref( $_[0] ) eq 'HASH' ) {
                        my $data = $_[0];
                        my $json = encode_json($data);
                        return $json;
                    }
                    else {
                        die
"Job data must be a HASH ref when putting on the queue\n";
                    }
                }
                else {
                    die
                      "Job data must be a HASH ref when putting on the queue\n";
                }
            },
        }
    );

    #connect to beanstalkd
    $bsclient->connect();
    if ( not $bsclient->socket() ) {
        $error = $bsclient->error() || '';
        logging("Could not connect to Beanstalk: $error");
        return;
    }

    return $bsclient;
}

sub error {
    if ($verbose) {
        print STDERR shift;
        print STDERR "\n";
    }
    return 1;
}

sub debug {

    #alias for error() at the moment
    error(shift);
    return 1;
}

sub logging {

    #alias for error() at the moment
    error(shift);
    return 1;
}
