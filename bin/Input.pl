#!/usr/bin/env perl

use strict;
use lib '../lib';
use File::Pid;
use Config::Auto;
use Log::Dispatch::Config;
use Getopt::Long;
use JSON::XS;
use POSIX;
use Grapture::Common::JobsInterface;
use Grapture::Common::Config;
use Grapture::Storage::MetaDB;

my $config;
my $cfgfile;
my $interval;
my $daemon;
my $reload;
my $run    = 1;
my $ident  = 'Input Daemon';

# Process command line options
my $optsOk = GetOptions(
    'cfgfile|c=s'  => \$cfgfile,
    'interval|i=i' => \$interval,
    'daemon|d'     => \$daemon,
) or die "Invalid options.\n";

unless ( $cfgfile and -f $cfgfile ) {
    die "Config file not specified or does not exist\n";
}

Log::Dispatch::Config->configure($cfgfile);
my $logger = Log::Dispatch::Config->instance;
$logger->{'outputs'}->{'syslog'}->{'ident'} = 'PollerInput';

#some signal handling
$SIG{HUP}     = sub { $reload++ };
$SIG{__DIE__} = sub { die @_ if $^S; $logger->critical(@_); };
$SIG{TERM}    = sub { $run = 0 };
$SIG{INT}     = sub { $run = 0 };

if ($daemon) {
    daemonize();
}

# Check if this process is already running, Don't run twice!
my ($thisFile) = $0 =~ m|([^/]+)$|;
my $pidfile = File::Pid->new( { 'file' => "/var/tmp/$thisFile.pid" } );
die "Process is already running\n" if $pidfile->running;
$pidfile->write or die "Could not create pidfile: $!\n";

#Init notices
$logger->notice('Input Daemon: Input starting...');
$logger->notice("Input Daemon: Using config file $cfgfile");

if ($interval) {
    $logger->notice("Input Daemon: Submitting jobs every $interval seconds.");
}
else {
    $logger->notice('Input Daemon: Submitting a single batch of jobs.');
}

loadConfig();
my $metaDB       = Grapture::Storage::MetaDB->new();
my $jobInterface = Grapture::Common::JobsInterface->new();

#Main loop
while ($run) {
    if ($reload) { loadConfig(); $reload = 0 }
    
    $logger->info('Input Daemon: Getting polling target metrics');
    my $polls = $metaDB->getMetricPolls();
    $logger->info('Input Daemon: Got '.scalar @{$polls}.' metrics to poll.');
    
    my %jobs;

    for my $job ( @{ $polls } ) {

        #stuff from the DB
        my $target        = $job->{'target'};
        my $metricDetails = {
            'metric'      => $job->{'metric'},
            'device'      => $job->{'device'},
            'valbase'     => $job->{'valbase'},
            'mapbase'     => $job->{'mapbase'},
            'counterbits' => $job->{'counterbits'},
            'category'    => $job->{'category'},
            'max'         => $job->{'max'},
            'valtype'     => $job->{'valtype'},
        };

        unless ( $jobs{$target} ) {
            $jobs{$target} = {
                'process'        => $job->{'module'},
                'output'         => $job->{'output'},
                'waitTime'       => 300,
                'processOptions' => {
                    'target'    => $target,
                    'version'   => $job->{'snmpversion'},
                    'community' => $job->{'snmpcommunity'},
                    'metrics'   => [],
                },
                'outputOptions' => {},
            };
        }

        push @{ $jobs{$target}->{'processOptions'}->{'metrics'} },
          $metricDetails;
    }

    my @jobList;

    for my $key ( keys %jobs ) {
        push @jobList, $jobs{$key};
    }
    
    $logger->info('Input Daemon: Submitting '.scalar @jobList.' job(s)');
    $jobInterface->submitJobs(\@jobList);
    $logger->info('Input Daemon: '.scalar @jobList.' job(s) added.');
    
    last unless $interval;
    sleep $interval;
}

## SUBs
sub loadConfig {

    $logger->info('Input Daemon: Loading config');
    $config = Grapture::Common::Config->new($cfgfile);
    $logger->info('Input Daemon: Config loaded');

    return 1;
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

    1;
}

$pidfile->remove;
$logger->notice('Input Daemon: Shutting Down');
exit;
