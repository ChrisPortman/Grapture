#!/usr/bin/env perl
#$Id: testInput.pl,v 1.9 2012/06/07 03:43:34 cportman Exp $

use strict;
use Config::Auto;
use Log::Dispatch::Config;
use Getopt::Long;
use JSON::XS;
use DBI;
use POSIX;

my $fifo;
my $dbh;
my $sth;
my $config;
my $cfgfile;
my $interval;
my $daemon;
my $reload = 1;
my $run    = 1;
my $ident  = 'PollerInput';


# Process command line options
my $optsOk = GetOptions(
    'cfgfile|c=s'  => \$cfgfile,
    'interval|i=i' => \$interval,
    'daemon|d'     => \$daemon,
) 
  or die "Invalid options.\n";


unless ( $cfgfile and -f $cfgfile ) {
    die "Config file not specified or does not exist\n";
}

Log::Dispatch::Config->configure($cfgfile);
my $logger = Log::Dispatch::Config->instance;
$logger->{'outputs'}->{'syslog'}->{'ident'} = 'PollerInput';

if ($daemon) {
	daemonize();
}

#Init notices
$logger->notice('Input starting...');
$logger->notice("Using config file $cfgfile");

if ($interval) {
    $logger->notice("Submitting jobs every $interval seconds.");
}
else {
    $logger->notice('Submitting a single batch of jobs.');
}

#some signal handling
$SIG{HUP}     = sub { $reload++ };
$SIG{__DIE__} = sub { $run = 0 };
$SIG{TERM}    = sub { $run = 0 };
$SIG{INT}     = sub { $run = 0 };

#Job harvesting query
my $getSchedQuery = q/select 
                     a.target,  a.device,      a.metric, a.valbase,
	                 a.mapbase, a.counterbits, a.max,    a.category,
	                 a.module, a.output, a.valtype, b.snmpcommunity,
	                 b.snmpversion
                     from targetmetrics a
                     join targets b on a.target = b.target
                     where a.enabled = true
                     order by a.target, a.metric --/;

#Main loop
while ($run) {
    if ($reload) { loadConfig(); $reload = 0 }

    my $res = $sth->execute();

    my %jobs;

    for my $job ( @{ $sth->fetchall_arrayref( {} ) } ) {

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
                'module'      => $job->{'module'},
                'output'      => $job->{'output'},
                'waitTime'    => 300,
                'methodInput' => {
                    'target'    => $target,
                    'version'   => $job->{'snmpversion'},
                    'community' => $job->{'snmpcommunity'},
                    'metrics'   => [],
                },
            };
        }

        push @{ $jobs{$target}->{'methodInput'}->{'metrics'} }, $metricDetails;
    }

    my @jobList;

    for my $key ( keys %jobs ) {
        push @jobList, $jobs{$key};
    }

    my $encodedJobs = encode_json( \@jobList );

    if ( -p $fifo ) {
        open( my $fifoFH, '>', $fifo )
          or ( $logger->emergency(q|Could not open FIFO, can't continue.|)
            and die );

        print $fifoFH "$encodedJobs\n";

        close $fifoFH;
    }
    else {
        $logger->emergency('FIFO not created, is the pollerMaster running?');
        exit;
    }

    last unless $interval;
    sleep $interval;
}

## SUBs
sub getConfig {
    my $file = shift;
    return unless ( $file and -f $file );
    my $config = Config::Auto::parse($file);
    return $config;
}

sub loadConfig {

    $logger->info('Loading config');
    $config = getConfig($cfgfile);
    $fifo   = $config->{'MASTER_FIFO'};
    my $DBHOST = $config->{'DB_HOSTNAME'};
    my $DBNAME = $config->{'DB_DBNAME'};
    my $DBUSER = $config->{'DB_USERNAME'};
    my $DBPASS = $config->{'DB_PASSWORD'};

    $dbh->disconnect if $dbh;    # disconnect if connected
    $dbh = DBI->connect(
        "DBI:Pg:dbname=$DBNAME;host=$DBHOST", $DBUSER, $DBPASS,

        #{'RaiseError' => 1},
      )
      or ( $logger->emergency("Failed to connect to the database: $DBI::errstr")
        and exit );

    $sth = $dbh->prepare($getSchedQuery);

    return 1
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

$logger->notice('Shutting Down');
exit;
