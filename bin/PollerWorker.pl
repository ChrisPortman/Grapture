#!/usr/bin/env perl
# $Id: PollerWorker.pl,v 1.16 2012/05/30 04:48:56 cportman Exp $

=head1 NAME

  PollerWorker.pl

=head1 SYNOPSIS

  PollerWorker.pl -s <beanstalk_server> -p <beanstalk_port>

=head1 DESCRIPTION

  Takes configuration from an XML file and creates and manages a
  JobsDoer object
  
=cut

use strict;
use warnings;

use lib '/home/chris/git/Grasshopper/lib';
use Sys::Hostname qw(hostname);
use JSON::XS;
use Getopt::Long;
use Data::Dumper;
use Jobsdoer;
use XML::Simple;
use POSIX;
use Log::Dispatch::Config;
use Log::Any::Adapter;

#Setup
my $bsserver;
my $bsport;
my $bsclient;
my @bstubes;
my $debug;
my $cfgfile;
my $logcfg;
my $daemon;

$|++;

my $optsOk = GetOptions(
    'cfgfile|c=s'   => \$cfgfile,
    'logcfg|l=s'    => \$logcfg,
    'daemon|d'      => \$daemon,
)
  or die "Invalid options\n";

#Setup logging
Log::Dispatch::Config->configure($logcfg);
my $logger = Log::Dispatch::Config->instance;
$logger->{'outputs'}->{'syslog'}->{'ident'} = 'JobWorker';
Log::Any::Adapter->set( 'Dispatch', dispatcher => $logger );

#daemonize here if appropriate.
if ($daemon) {
    daemonize();	
}

unless ( $cfgfile and -f $cfgfile ) {
	$logger->emergency('Require an existing configuration file (-c)');
	exit;
}

=head1 USAGE

FIXME

=cut

#Load the config file
loadConfig($cfgfile)
  or ($logger->emergency('Config file invalid') and exit);

#create a jobsdoer object with the Beanstalk details
$bsserver .= ':' . $bsport if $bsport;
my $jobsDoer = Jobsdoer->new(
    {
        'bsserver' => $bsserver,
        'bstubes'  => \@bstubes,
    }
);

# Setup a HUP handler to refresh available job modules.
# kill -HUP <pid>
$SIG{HUP}  = \&HUPHANDLE; 
$SIG{CHLD} = \&REAPER;
$SIG{INT}  = \&HUNTSMAN;
$SIG{TERM} = \&HUNTSMAN;

#Start a loop that will continually attempt to start threads.
my $run = 1;

MAINLINE:
while ($run) {    #loop almost indefinitely

    #start a thread if there are free slots.
    $logger->info('Looking to start thread...');
    my $thread = $jobsDoer->startThread();

    $logger->info('Started $thread. '.$jobsDoer->{'childCount'}.' running') if $thread;
    $logger->info('Slots are full.') unless $thread;

    #Keep going round as long as threads are created
    next if $thread;

    #Otherwise sleep till a sig wakes us.
    sleep;
}

exit 1;

############# Sub Routines ###############

sub loadConfig {
    my $cfgfile = shift;
    $logger->info('Loading config file '.$cfgfile);

    #read in the xml
    my $rawConfig = XMLin($cfgfile);

    my %config;
    $config{'Poller'} = {};
    $config{'Tubes'}  = [];

    my $hostname = hostname()
      or warn "Could not get hostname: $!\n";
    chomp($hostname);

    #Parse the Poller settings (Beanstalk server port etc)
    for my $key ( keys $rawConfig->{'Pollers'}->{'Defaults'} ) {

        #Load the defaults into the poller settings first
        $config{'Poller'}->{$key} =
          $rawConfig->{'Pollers'}->{'Defaults'}->{$key};
    }

    if ( $rawConfig->{'Pollers'}->{$hostname} ) {
        for my $key ( keys $rawConfig->{'Pollers'}->{$hostname} ) {

            #Load the host specific poller settings over the defaults.
            $config{'Poller'}->{$key} =
              $rawConfig->{'Pollers'}->{'Defaults'}->{$key};
        }
    }

    #Work out what tubes we're subscribing to.
    for my $tube ( keys( $rawConfig->{'Tubes'} ) ) {
        my %pollers =
          map { $_ => 1 } @{ $rawConfig->{'Tubes'}->{$tube}->{'Poller'} };

        if ( $pollers{$hostname} ) {
            push @{ $config{'Tubes'} }, ($tube);
            print "Subscribing to tube $tube\n";
        }
    }
    
    #pick out the config elements.
	$bsserver = $config{'Poller'}->{'Server'};
	$bsport   = $config{'Poller'}->{'Port'};
	@bstubes  = @{ $config{'Tubes'} };
	
	unless ($bsserver and $bsport and scalar @bstubes) {
		return;
	}

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
	
	chdir "/";
	umask 0;
	
	open (STDIN,  "</dev/null");
	open (STDOUT, ">/dev/null");
	open (STDERR, ">&STDOUT"  );

	1;
}

# Set up sig handlers
sub REAPER {
	# Ditch dead children.
	my $pid;
	
	$pid = waitpid(-1, &WNOHANG);
	
	while ( $pid > 0 ) {
		print "Child $pid is dead. Throw it away.\n";
		$jobsDoer->{'childCount'} --;
		delete $jobsDoer->{'childPids'}->{$pid};
		
		$pid = waitpid(-1, &WNOHANG);
    }	
	1;	
}

sub HUNTSMAN {
	# Murder all the children.
	$run = 0;
    $logger->notice('Shutting Down.  Waiting for worker processes');
    
    kill 'INT', keys %{ $jobsDoer->{'childPids'} };
    
    while ( $jobsDoer->{'childCount'} ) {
		$logger->notice("$jobsDoer->{'childCount'} workers left.");
		sleep;
	}
	
	$logger->notice('All workers are gone.  Goodbye');

	exit;	
}

sub HUPHANDLE {
    $logger->info('HUP received!');

    $jobsDoer->loadModules();
    kill 'INT', keys %{ $jobsDoer->{'childPids'} };
};

