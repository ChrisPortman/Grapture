#!/usr/bin/env perl

=head1 TITLE

  JobsDoer
  
=head1 DESCRIPTION

  JobsDoer is a Object Orientated interface to a Beanstalkd server. It
  retireved jobs from the server and dispatces them to doer modules that
  will interperet the jobs data, perform some specific processes with it
  and return a result.  The result is then dispatched to an Output
  module that is responsible to getting the result to where it needs to
  go.

=head1 THREADS

  The JobsDoer was designed to run threaded so that a single host can
  simultaneously take and run multiple jobs.
  
  Once the object has been created with the new() constructor, the 
  startThread() method will start a thread and return the thread ID. The
  thread will then go off and handle the process flow within its self.
  
  In theory, the object could be used by manually calling the individual
  methods, but this has not been proven.
  
  As a precaution against unpredicted thread failure/behavior a thread
  has a finite life time.  This can be set at the time of construction
  and defaults to 1 hour, at expiry, the thread will finish the current
  job and then exit.
  
  The constructor also accepts a maxThreads value which limits the number
  of concurrently running threads.  It is set to 4 be default. Any
  invokations of the startThread() method will first see if there are
  any free thread slots and if not return an undef.  This should not be
  considered in error.  Typical usage would be to start an infinite loop
  that attempts to start threads, then they will be spawned by JobsDoer
  as required.
  
=head1 MODULES

  JobsDoer dynamically includes modules on start up and if a HUP is
  received.
  
=head2 Doer Modules

  Doer modules fall under the Jobsdoer::Doer namespace and represent the
  actual feet on the ground so to speak.  They contain the actual logic
  that gets something done/does the job.
  
=head2 Output Modules

  Output modules fall under Jobsdoer::Output namespace and are tasked
  with getting the result of the Doer module to some place useful and 
  in a useful fassion.  They may include manipulating the result in a
  way thats specific and appropriate for the output destination.
  
  An output modules may include one that puts a result in a database or
  graphs the result.
  
  There can only be one output per job at the moment.  May change this
  later.  Also, generally output modules dont have to be compatible with
  more than one Doer.  Its really up to the author of the Output module
  what Doers it will work with.
  
=head2 TODO

  - Fix up some inconsistancies in terminologies in the code variables
    e.g. Doer modules being refered to as methods and modules 
    interchangably.

=cut

package Grapture::JobsProcessor;

use strict;
use warnings;

#use threads;
use POSIX;
use Sys::Hostname qw(hostname);
use Beanstalk::Client;
use JSON::XS;
use Data::Dumper;
use Log::Any qw ( $log );
use Cwd;

#Use plugable modules to allow on the fly expansion of functionality
use Module::Pluggable
  search_path => ['Grapture::JobsProcessor::Modules'],
  except      => qr/^Grapture::JobsProcessor::Modules::.+::/, #limit to 1 level.
  require     => 1,
  sub_name    => 'modules';

sub new {
    my $class = shift;
    $class = ref $class if ref $class;

    my $args = shift;

    die 'Argument to ' . $class . '->new() must be a hash ref'
      unless ref $args eq 'HASH';

    die 'Args hash must contain at least bsclient and bstubes.'
      unless ( $args->{'bsserver'} and $args->{'bstubes'} );

    my $self = bless( {}, $class );

    $self->{'bsserver'} = $args->{'bsserver'};
    $self->{'bstubes'}  = $args->{'bstubes'};

    #These values can be suplied in %args or given defaults here.
    $self->{'maxThreadTime'} = $args->{'maxThreadTime'} || 3600;
    $self->{'maxThreads'}    = $args->{'maxThreads'}    || 1;
    $self->{'childCount'}    = $args->{'childCount'}    || 0;
    $self->{'childPids'}     = {};

    #Initial load of plugable modules.
    $self->loadModules();

    #Create Beanstalk obj (doesnt actually connect)
    $self->{'bsclient'} = Beanstalk::Client->new(
        {
            server  => $self->{'bsserver'},
            encoder => sub {

                #Use only a single arg that must be an ref
                if ( ref( $_[0] ) ) {
                    my $data = $_[0];
                    my $json = encode_json($data);
                    return $json;
                }
                else {
                    die "Job data must be a ref when putting on the queue\n";
                }
            },
        }
    );

    return $self;
}

sub startThread {
    my $self = shift;
    my $pid;

    return if ( $self->{'childCount'} >= $self->{'maxThreads'} );

    # block signal for fork
    my $sigset = POSIX::SigSet->new(SIGINT);
    sigprocmask( SIG_BLOCK, $sigset )
      or die "Can't block SIGINT for fork: $!\n";

    #spin off a thread.
    die "fork: $!" unless defined( $pid = fork );

    if ($pid) {

        # unblock signals
        sigprocmask( SIG_UNBLOCK, $sigset )
          or die "Can't unblock SIGINT for fork: $!\n";

        $self->{'childCount'}++;
        $self->{'childPids'}->{$pid} = 1;

        return $pid;
    }
    else {
        # unblock signals
        sigprocmask( SIG_UNBLOCK, $sigset )
          or die "Can't unblock SIGINT for fork: $!\n";

        $self->_jobDoerThread( time() + $self->{'maxThreadTime'} );

        exit;
    }
}

sub loadModules {
    my $self = shift;
    
    # First clear any pluggable modules from %INC so they are reloaded.
    $log->info('Looking for modules that need clearing to be reloaded');
    if ( $self->{'modules'} ) {
        $log->info('Clearing modules...');
        for my $module ( keys %{ $self->{'modules'} } ) {
            my $incmod = $self->{'modules'}->{$module}.'.pm';
            $incmod =~ s|::|/|g;
            $log->info('Clearing ' . $self->{'modules'}->{$module});
            
            if ( $INC{ $incmod } ) {
                $log->info('Clearing module ' . $incmod . ' from %INC');
                delete $INC{ $incmod }
            }
        }
    }

    #Stash the available pluggins in %modules, then to the object.
    my %modules = map {
        my $mod = $_;
        $mod =~ s/^Grapture::JobsProcessor::Modules:://;
        $mod => $_
    } $self->modules();

    
    $log->info("Loading modules...");
    
    for my $module ( keys %modules ) {
		$log->info("Loaded process module $module");
	}
	
    $self->{'modules'}   = \%modules;

    return 1;
}

sub beanstalkConnect {
    my $self        = shift;
    my $bsclientObj = $self->{'bsclient'};

    $bsclientObj->connect();

    if ( $bsclientObj->socket() ) {
        return 1;
    }

    return;
}

sub beanstalkDisconnect {
    my $self        = shift;
    my $bsclientObj = $self->{'bsclient'};

    $bsclientObj->quit()
        if $bsclientObj->socket();

    return 1;
}

sub getJob {
    my $self        = shift;
    my $bsclientObj = $self->{'bsclient'};
    $bsclientObj->watch_only( @{ $self->{bstubes} } );

    my $job = $bsclientObj->reserve(10);

    return $job if $job;

    return;
}

sub runJob {
    my $self = shift;
    my $job  = shift;

    return unless $job;
    
    $log->debug('Processing job');
    debug(  "Starting job ID $job->{'id'} at ". localtime() );

    my $jobData = decode_json( $job->{'data'} );

    $log->debug("Job details $job->{'id'}, logs tube $jobData->{'logsTube'}");
    
    #Stash some useful details regarding the job
    $self->{'currentJobData'} = {
        'jobId'          => $job->{'id'},
        'jobData'        => $jobData,
        'process'        => $jobData->{'process'},
        'logsTube'       => $jobData->{'logsTube'},
    };

    unless (    $self->{'currentJobData'}->{'jobData'}
            and ref $self->{'currentJobData'}->{'process'} )
    {
        $self->log('Received malformed job data.  Job will be deleted.');
        $self->{'bsclient'}->delete( $self->{'currentJobData'}->{'jobId'} );
        return 2;
    }

    my $result = $self->runProcess();

    return $result;
}

sub runProcess {
    my $self    = shift;
    my $process  = $self->{'currentJobData'}->{'process'};
    my $jobId   = $self->{'currentJobData'}->{'jobId'};

    unless ( $process or  $jobId ) {
        $self->log('Did not get the required details');
        return;
    }
    
    my $result;
    my $status = 1; #default to unknown error

    for my $step ( @{$self->{'currentJobData'}->{'process'}} ) {
        my $module  = $step->{'name'};
        my $options = $step->{'options'} || {};

        unless ( $self->{'modules'}->{$module} ) {
            $self->log("Module specified ($module) is not valid");
            $status = 3;
            last;
        }
    
        eval {
            #Call run() of the module as a method call so that
            #inheritance works within the module.  we're not getting an
            #object back.
            my $package = $self->{'modules'}->{$module};
            $result = $package->run($options, $result);
                        
            unless ($result) {
                $self->log("$module did not return a result for $jobId");
                $status = 4;
            }
            
            1;
        };
    
        if ($@) {
            my $error = $@;
            $log->error("Process module $module returned error $error");
            $self->log($error);
            $status = 5;
        }
        
        last unless $status == 1;        
    }

    return $status;
}

sub deleteJob {
    my $self = shift;

    if ( $self->{'currentJobData'} and $self->{'currentJobData'}->{'jobId'} ) {
        my $bsclientObj = $self->{'bsclient'};

        $bsclientObj->delete( $self->{'currentJobData'}->{'jobId'} );
        debug(  'Finishing job ID '
              . $self->{'currentJobData'}->{'jobId'} . ' at '
              . localtime() );
    }

    return 1;
}

sub log {
    my $self    = shift;
    my $message = shift;
    my $code    = shift;
    my $jobId   = $self->{'currentJobData'}->{'jobId'};

    if ( $self->{'currentJobData'} ) {
        if ( $self->{'currentJobData'}->{'logsTube'} ) {
            my $bsclientObj = $self->{'bsclient'};

            #build the job data.
            my %logentry = (
                'worker'  => hostname(),
                'message' => $message,
                'code'    => $code || undef,
            );
            $logentry{'jobId'} = $jobId || 'NULL';

            #send the message to the master via the logs tube
            $bsclientObj->use( $self->{'currentJobData'}->{'logsTube'} );
            $bsclientObj->put( {}, \%logentry );
        }
    }
    return 1;
}

sub debug {
    my $message = shift;
    my $threadid = $$ || 'UNKNOWN';

    $log->info("Thread ID $threadid - $message");

    return 1;
}

###########################################
#            Private Subs                 #
###########################################

sub _jobDoerThread {
    my $self        = shift;
    my $expireTime  = shift;
    my $bsclientObj = $self->{'bsclient'};
    my $exit;

    local $SIG{'INT'} = sub {
        debug('Need to exit. Exit flag set, alarm set for 15 secs.');
        alarm 15;
        $exit = 1;
    };

    #Connect to the Beanstalk server.
    if ( not $self->beanstalkConnect() ) {
        sleep 10;    #Avoid spamming the CPU if the BS server is down
                     #~ threads->detach();
        return;
    }

    debug('Connected to Beanstalk server');

    while ( not $exit ) {

        my $jobObj;
        my $result = 0;
        my $submit;

        #Check to see if we are still connected
        last if not $bsclientObj->socket();

        #run each step as long as the last returns true.
        $jobObj = $self->getJob();
        if ($jobObj) {

            $result = $self->runJob($jobObj);

            $self->deleteJob();

            $self->log( 'Job complete', $result );
        }

        if ( $expireTime and time > $expireTime ) {
            $exit++;
        }
    }

    #Disconnect from the BS server properly
    $self->beanstalkDisconnect();

    debug('Expired, exiting');

    return 1;
}

1;
