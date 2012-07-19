#!/usr/bin/env perl
# $Id: Jobsdoer.pm,v 1.15 2012/06/07 03:41:22 cportman Exp $

=head 1 TITLE

  JobsDoer.pm
  
head 1 DESCRIPTION

  JobsDoer is a Object Orientated interface to a Beanstalkd server. It
  retireved jobs from the server and dispatces them to doer modules that
  will interperet the jobs data, perform some specific processes with it
  and return a result.  The result is then dispatched to an Output
  module that is responsible to getting the result to where it needs to
  go.

head 1 THREADS

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
  
=head 1 MODULES

  JobsDoer dynamically includes modules on start up and if a HUP is
  received.
  
=head 2 Doer Modules

  Doer modules fall under the Jobsdoer::Doer namespace and represent the
  actual feet on the ground so to speak.  They contain the actual logic
  that gets something done/does the job.
  
=head 2 Output Modules

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
  
=head 2 TODO

  - Fix up some inconsistancies in terminologies in the code variables
    e.g. Doer modules being refered to as methods and modules 
    interchangably.

=cut


package Jobsdoer;

use strict;
use warnings;

#use threads;
use POSIX;
use Sys::Hostname qw(hostname);
use Beanstalk::Client;
use JSON::XS;
use Data::Dumper;

#Use plugable modules to allow on the fly expansion of functionality
use Module::Pluggable search_path => ['Jobsdoer::Doer'],   require => 1, sub_name => 'doers';
use Module::Pluggable search_path => ['Jobsdoer::Output'], require => 1, sub_name => 'outputs';

sub new {
    my $class = shift;
    if ( ref($class) ) { $class = ref($class); }

    my $args = shift;

    if ( not( ref($args) or ref( $args eq 'HASH' ) ) ) {
        die 'Argument to Jobsdoer->new() must be a hash ref';
    }

    if ( not( $args->{'bsserver'} and $args->{'bstubes'} ) ) {
        die 'Args hash must contain at least bsclient and bstubes.';
    }

    my $self = bless( $args, $class );

    #These values can be suplied in %args or given defaults here.
    $self->{'maxThreadTime'} ||= 3600;
    $self->{'maxThreads'}    ||= 5;
    $self->{'childCount'}      = 0;
    $self->{'childPids'}       = {};

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
    
    if ( $self->{'childCount'} >= $self->{'maxThreads'} ) {
		return;
	}
    
    # block signal for fork
    my $sigset = POSIX::SigSet->new(SIGINT);
    sigprocmask(SIG_BLOCK, $sigset)
        or die "Can't block SIGINT for fork: $!\n";
    
    #spin off a thread.
    die "fork: $!" unless defined ($pid = fork);
      
    if ( $pid ) {
		# unblock signals
		sigprocmask(SIG_UNBLOCK, $sigset)
            or die "Can't unblock SIGINT for fork: $!\n";
		
		$self->{'childCount'} ++;
		$self->{'childPids'}->{$pid} = 1;
		
		return $pid;
	}
	else {
		# unblock signals
		sigprocmask(SIG_UNBLOCK, $sigset)
            or die "Can't unblock SIGINT for fork: $!\n";
		
		$self->_jobDoerThread( time() + $self->{'maxThreadTime'} );
		
		exit;
	}
}

sub loadModules {
    my $self = shift;

    #Stash the available pluggins in %modules, then to the object.
    my %doers = map {
        my $mod = $_;
        $mod =~ s/^Jobsdoer::Doer:://;
        $mod => $_
    } $self->doers();

    my %outputs = map {
        my $mod = $_;
        $mod =~ s/^Jobsdoer::Output:://;
        $mod => $_
    } $self->outputs();


    $self->{'doers'}   = \%doers;
    $self->{'outputs'} = \%outputs;
    
    return 1;
}

sub purgeNonactiveThreads {
    my $self = shift;

    #clean out the active thread list
    my %currentThreads = map { $_->tid() => 1 } threads->list();
    for my $activeThread ( keys %{ $self->{'activeThreads'} } ) {
        delete $self->{'activeThreads'}->{$activeThread}
          if not $currentThreads{$activeThread};
    }

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

    if ( $bsclientObj->socket() ) {
        $bsclientObj->quit();
    }
    return 1;
}

sub getJob {
    my $self        = shift;
    my $bsclientObj = $self->{'bsclient'};
    $bsclientObj->watch_only( @{ $self->{bstubes} } );

    my $job = $bsclientObj->reserve(10);

    if ($job) {
        return $job;
    }

    return;
}

sub runJob {
    my $self = shift;
    my $job  = shift;

    if ( not $job ) { return; }

    my $bsclientObj = $self->{'bsclient'};

    my $jobData = decode_json( $job->{'data'} );
    debug("Starting job ID $job->{'id'} at ".localtime()." for $jobData->{'methodInput'}->{'target'}");

    #Stash some useful details regarding the job
    $self->{'currentJobData'} = {
        'jobId'       => $job->{'id'},
        'jobData'     => $jobData,
        'module'      => $jobData->{'module'},
        'outModule'   => $jobData->{'output'},
        'methodInput' => $jobData->{'methodInput'},
        'resultsTube' => $jobData->{'resultsTube'},
        'logsTube'    => $jobData->{'logsTube'},
    };

    if (
        not(    $self->{'currentJobData'}->{'jobData'}
            and $self->{'currentJobData'}->{'module'} )
      )
    {
        $self->log('Received malformed job data.  Job will be deleted.');
        $bsclientObj->delete( $self->{'currentJobData'}->{'jobId'} );
    }

    my $result = $self->runDoerModule();
    
    my %resultData;
    
    if ($result) {
		
        %resultData = (
            'id'         => $self->{'currentJobData'}->{'jobId'},
            'result'     => $result,
        );
        
        return wantarray ? %resultData : \%resultData;
    }
    
    return;

}

sub runDoerModule {
    my $self   = shift;
    my $module = $self->{'currentJobData'}->{'module'};
    my $data   = $self->{'currentJobData'}->{'methodInput'};
    my $jobId  = $self->{'currentJobData'}->{'jobId'};
    
    if ( not( $module or $data or $jobId ) ) {
        $self->log('Did not get the required details');
        return;
    }

    if ( not $self->{'doers'}->{$module} ) {
        $self->log("Module specified ($module) is not valid");
        return;
    }

    my $result;
    my $error;

    eval {
        my $work = $self->{'doers'}->{$module}->new($data);
        $work or die "Couldn't construct object for module $module";
        
        $result  = $work->run();
          
        unless ($result) {
			$error   = $work->error();
        
	        if ($error) {
		        $self->log($error);
			}        
		}
		
        1;
    };
    
    if ($@) {
        $self->log($@);
        return;
    }

    if ($result) {
        return $result;
    }

    return;
}

sub runOutputModule {
    my $self   = shift;
    my $result = shift;
    my $module = $self->{'currentJobData'}->{'outModule'};
    
    if ( not( $module ) ) {
		#If theres no module, just return, this is valid as it may be
		#desired to just get the result back via Beanstalk.
        return;
    }

    if ( not $self->{'outputs'}->{$module} ) {
        $self->log("Output module specified ($module) is not valid");
        return;
    }

    my $error;
    my $resultData = $result->{'result'};
    
    eval {
        my $work = $self->{'outputs'}->{$module}->new($resultData);
        
        if ($work) {
        
            $result = $work->run();
	        $error  = $work->error();
        
	    }
	    
        1;
    };

    if ($@) {
		print "Whoops!\n";
        $self->log($@);
        return;
    }

    if ($result) {
        return $result;
    }

    return;
}

sub submitResult {
    my $self       = shift;
    my $result     = shift;

    if (
        not(    $self->{'currentJobData'}
            and $self->{'currentJobData'}->{'jobId'} )
      )
    {

        #there has been no job
        return;
    }

    if ( $result ) {

		$self->runOutputModule($result)
		  or warn "Output module returned a failure\n";

    }
    else {

        #we should have a result
        $self->log('Module run failed and/or did not return a result');

		$result = {
            'id'     => $self->{'currentJobData'}->{'jobId'},
            'result' => 0,
        };

	}

	#submit the result back through the tubes regardless of success
	#or not as it will have any error messages.		
    my $bsclientObj = $self->{'bsclient'};

    $bsclientObj->use( $self->{'currentJobData'}->{'resultsTube'} );
    $bsclientObj->put( {}, $result );
    
    return 1;
}

sub deleteJob {
    my $self = shift;

    if ( $self->{'currentJobData'} and $self->{'currentJobData'}->{'jobId'} ) {
        my $bsclientObj = $self->{'bsclient'};

        $bsclientObj->delete( $self->{'currentJobData'}->{'jobId'} );
        debug('Finishing job ID '.$self->{'currentJobData'}->{'jobId'}.' at '.localtime());
    }
    
    $self->{'currentJobData'} = undef;

    return 1;
}

sub log {
    my $self    = shift;
    my $message = shift;
    my $jobId   = $self->{'currentJobData'}->{'jobId'};

    if ( $self->{'currentJobData'} ) {
        if ( $self->{'currentJobData'}->{'logsTube'} ) {
            my $bsclientObj = $self->{'bsclient'};

            #build the job data.
            my %logentry = (
                'worker'  => hostname(),
                'time'    => scalar(gmtime),
                'message' => $message,
            );
            $logentry{'jobId'} = $jobId || 'NULL';

            #send the message to the master via the logs tube
            $bsclientObj->use( $self->{'currentJobData'}->{'logsTube'} );
            $bsclientObj->put( {}, \%logentry );
        }
    }
    else {
        print STDERR "$message\n";
    }

    return 1;
}

sub debug {
	my $message = shift;
	my $threadid = $$ || 'UNKNOWN';
	
	print "Thread ID $threadid - $message\n";
	
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
		my $result;
		my $submit;

        #Check to see if we are still connected
        last if not $bsclientObj->socket();

        #run each step as long as the last returns true.
            ( $jobObj = $self->getJob()              ) 
        and ( $result = $self->runJob($jobObj)       )
        and ( $submit = $self->submitResult($result) );
        
        
        $submit or  $self->submitResult();
        $jobObj and $self->deleteJob();
        
        if ( $expireTime and time > $expireTime ) {
			print "Thread has expired and is ending\n";
			$exit ++;
		}
    }

    #Disconnect from the BS server properly
    $self->beanstalkDisconnect();

    debug('Expired, exiting');
    
    return 1;
}

1;
