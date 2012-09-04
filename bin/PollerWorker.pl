#!/usr/bin/env perl

=head1 NAME

  PollerWorker.pl

=head1 USAGE

  PollerWorker.pl -c <config file> [-d]
  
      -c|--cfgfile : Full path to configuration file
      -d|--daemon  : Daemonize the process.

=head1 DESCRIPTION

  Takes configuration from configuration file specified by -c which 
  should specify the Beanstalk server address, port and tube to watch as
  well as logging options.
  
=cut

use strict;
use warnings;

use lib '../lib';
use File::Pid;
use POSIX;
use Sys::Hostname qw(hostname);
use Getopt::Long;
use Config::Auto;
use Log::Dispatch::Config;
use Log::Any::Adapter;
use JSON::XS;
use GH::Jobsdoer;

#Setup
my $bsserver;
my $bsport;
my $bsclient;
my $bstube;
my $debug;
my $cfgfile;
my $daemon;

$|++;

# Setup handlers inc. a HUP handler to refresh available job modules.
# kill -HUP <pid>
$SIG{HUP}     = \&HUPHANDLE;
$SIG{CHLD}    = \&REAPER;
$SIG{INT}     = \&HUNTSMAN;
$SIG{TERM}    = \&HUNTSMAN;
$SIG{__DIE__} = \&dieHandle;

my $optsOk = GetOptions(
    'cfgfile|c=s' => \$cfgfile,
    'daemon|d'    => \$daemon,
) or die "Invalid options\n";

unless ( $cfgfile and -f $cfgfile ) {
    die "Require an existing configuration file (-c)\n";
}

#Setup logging
Log::Dispatch::Config->configure($cfgfile);
my $logger = Log::Dispatch::Config->instance;
$logger->{'outputs'}->{'syslog'}->{'ident'} = 'JobWorker';
Log::Any::Adapter->set( 'Dispatch', dispatcher => $logger );

#daemonize here if appropriate.
my $pidfile;
if ($daemon) {
    daemonize();
}

$logger->notice('POLLER WORKER STARTING UP');

#Load the config file
loadConfig($cfgfile)
  or ( $logger->critical('Config file invalid') and exit );

#create a jobsdoer object with the Beanstalk details
$bsserver .= ':' . $bsport if $bsport;
my $jobsDoer = GH::Jobsdoer->new(
    {
        'bsserver' => $bsserver,
        'bstubes'  => [$bstube],
    }
);

#Start a loop that will continually attempt to start threads.
my $run = 1;

MAINLINE:
while ($run) {    #loop almost indefinitely

    #start a thread if there are free slots.
    $logger->info('Looking to start thread...');
    my $thread = $jobsDoer->startThread();

    $logger->info(
        'Started $thread. ' . $jobsDoer->{'childCount'} . ' running' )
      if $thread;
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

    return unless ( $cfgfile and -f $cfgfile );
    my $config = Config::Auto::parse($cfgfile);

    $bsserver = $config->{'BS_SERVER'};
    $bsport   = $config->{'BS_PORT'};
    $bstube   = $config->{'BS_JOBQ'};

    if ( $bsserver and $bsport and $bstube ) {
        return 1;
    }

    return;
}

sub daemonize {
    POSIX::setsid or die "setsid: $!";
    my $pid = fork();

    if ( $pid < 0 ) {
        die "fork: $!";
    }
    elsif ($pid) {

        #Parent process exits leaving the daemonized process to run.
        exit 0;
    }

    chdir '/';
    umask 0;

    open( STDIN,  '<', '/dev/null' );
    open( STDOUT, '>', '/dev/null' );
    open( STDERR, '>&STDOUT' );

    # Check if this process is already running, Don't run twice!
    my ($thisFile) = $0 =~ m|([^/]+)$|;
    $pidfile = File::Pid->new( { 'file' => "/var/tmp/$thisFile.pid" } );
    die "Process is already running\n" if $pidfile->running;
    $pidfile->write or die "Could not create pidfile: $!\n";

    1;
}

# Set up sig handlers
sub REAPER {

    # Ditch dead children.
    my $pid;

    $pid = waitpid( -1, &WNOHANG );

    while ( $pid > 0 ) {
        print "Child $pid is dead. Throw it away.\n";
        $jobsDoer->{'childCount'}--;
        delete $jobsDoer->{'childPids'}->{$pid};

        $pid = waitpid( -1, &WNOHANG );
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
        sleep 2;
    }

    $pidfile->remove if $daemon;
    $logger->notice('All workers are gone.  Goodbye');

    exit;
}

sub HUPHANDLE {
    $logger->info('HUP received!');

    $jobsDoer->loadModules();
    kill 'INT', keys %{ $jobsDoer->{'childPids'} };
}

sub dieHandle {
    die @_ if $^S;    #Dont do anything special in an eval
    if ($logger) {
        $logger->critical(@_);
    }
    else {
        die @_;
    }
    return 1;
}

