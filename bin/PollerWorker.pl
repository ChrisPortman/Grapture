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

use lib '../lib';
use Sys::Hostname qw(hostname);
use JSON::XS;
use Getopt::Long;
use Data::Dumper;
use Jobsdoer;
use XML::Simple;
use POSIX;

$| ++;

#Setup
my $bsserver;
my $bsport;
my $bsclient;
my @bstubes;
my $debug;
my $cfgfile;
my $config;

my $optsOk = GetOptions(
    'msgserver|s=s' => \$bsserver,
    'msgport|p=s'   => \$bsport,
    'tubes|t=s'     => \@bstubes,
    'debug|d'       => \$debug,
    'cfgfile|c=s'   => \$cfgfile,
);
die "Invalid options\n" unless $optsOk;

=head1 USAGE

FIXME

=cut

#Load the config file, if a config file is specified, any options it
#supplies will take precedence over command line options.
if ($cfgfile) {
    $config = XMLin($cfgfile);
    $config = parseConfig($config);

    #pick out the config elements.
    $bsserver = $config->{'Poller'}->{'Server'}
      if $config->{'Poller'}->{'Server'};

    $bsport = $config->{'Poller'}->{'Port'}
      if $config->{'Poller'}->{'Port'};

    @bstubes = @{ $config->{'Tubes'} }
      if $config->{'Tubes'};
}


#create a jobsdoer object with the Beanstalk details
$bsserver .= ':' . $bsport if $bsport;
my $jobsDoer = Jobsdoer->new(
    {
        'bsserver' => $bsserver,
        'bstubes'  => \@bstubes,
    }
);

# Setup a HUP handler to refresh available job modules.
local $SIG{'HUP'} = sub {
    debugOut('HUP received!');

    $jobsDoer->loadModules();
    kill 'INT', keys %{ $jobsDoer->{'childPids'} };
};

$SIG{CHLD} = \&REAPER;
$SIG{INT}  = \&HUNTSMAN;
$SIG{TERM} = \&HUNTSMAN;

#Start a loop that will continually attempt to start threads.
my $run = 1;

MAINLINE:
while ($run) {    #loop almost indefinitely

    #start a thread if there are free slots.
    debugOut('Looking to start thread...');
    my $thread = $jobsDoer->startThread();

    debugOut('Started $thread. '.$jobsDoer->{'childCount'}.' running') if $thread;
    debugOut('Slots are full.') unless $thread;

    #Keep going round as long as threads are created
    next if $thread;

    #Otherwise sleep till a sig wakes us.
    sleep;
}

exit 1;

############# Sub Routines ###############

sub parseConfig {
    my $rawConfig = shift;
    if ( not ref($rawConfig) ) { return; }

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
            push @{ $config{'Tubes'} }, lc($tube);
            print "Subscribing to tube $tube\n";
        }
    }

    return wantarray ? %config : \%config;
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
	print "We need to exit.  Kill the children!\n";

    while ( $jobsDoer->{'childCount'} ) {
		print "Waiting for children to die, $jobsDoer->{'childCount'} left.\n";
		sleep;
	}

	exit;	
}

sub debugOut {
    if ( not $debug ) { return; }

    my $output = shift;
    chomp $output;
    print $output . "\n";

    return 1;
}
