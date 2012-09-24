#!/usr/bin/env perl

use strict;
use Getopt::Long;
use Config::Auto;
use Log::Dispatch::Config;
use JSON::XS;
use Data::Dumper;
use DBI;

my $cfgfile;

# Process command line options
my $optsOk = GetOptions( 'cfgfile|c=s' => \$cfgfile, );
die "Invalid options.\n" unless $optsOk;

unless ( $cfgfile and -f $cfgfile ) {
    die "Must supply valid config file (-c)\n";
}

#set up logging
Log::Dispatch::Config->configure($cfgfile);
my $logger = Log::Dispatch::Config->instance;
$logger->{'outputs'}->{'syslog'}->{'ident'} = 'Discovery';

my $GHCONFIG = getConfig($cfgfile);
my $fifo     = $GHCONFIG->{'MASTER_FIFO'};
my $DBHOST   = $GHCONFIG->{'DB_HOSTNAME'};
my $DBNAME   = $GHCONFIG->{'DB_DBNAME'};
my $DBUSER   = $GHCONFIG->{'DB_USERNAME'};
my $DBPASS   = $GHCONFIG->{'DB_PASSWORD'};

my $dbh = DBI->connect(
    "DBI:Pg:dbname=$DBNAME;host=$DBHOST",
    $DBUSER,
    $DBPASS,

    #{'RaiseError' => 1},
);

if ( not $dbh ) {
    $logger->emergency('Could not connect to databse');
    exit;
}

my $getTargetsQuery = q/select target, snmpversion, snmpcommunity
                       from targets
                       where lastdiscovered is NULL --/;

my $sth = $dbh->prepare($getTargetsQuery);
my $res = $sth->execute();

my $module = 'Discovery';
my $output = 'DiscoveryDB';
my @jobList;

for my $targetRef ( @{ $sth->fetchall_arrayref( {} ) } ) {
    my $target    = $targetRef->{'target'};
    my $version   = $targetRef->{'snmpversion'};
    my $community = $targetRef->{'snmpcommunity'};

    print "Adding job for $target\n";

    push @jobList,
      {
        'process'        => $module,
        'output'         => $output,
        'priority'       => 100,
        'processOptions' => {
            'target'    => $target,
            'version'   => $version,
            'community' => $community,
        },
        'outputOptions' => {
            'dbhost' => $DBHOST,
            'dbname' => $DBNAME,
            'dbuser' => $DBUSER,
            'dbpass' => $DBPASS,
        },
      };

    $logger->info("Queued discovery for $target");
}

unless (@jobList) {
    exit 1;
}

my $encodedJobs = encode_json( \@jobList );

unless ($encodedJobs) {
    exit 1;
}

if ( -p $fifo ) {
    open( my $fifoFH, '>', $fifo )
      or ( $logger->emergency(q/Could not open FIFO, can't continue./)
        and exit );

    print $fifoFH "$encodedJobs\n";
    $logger->info('Added discovery jobs');
    close $fifoFH;
}
else {
    $logger->emergency('FIFO not created, is the pollerMaster running?');
}

#SUBS
sub getConfig {
    my $file = shift;
    return unless ( $file and -f $file );
    my $config = Config::Auto::parse($file);
    return $config;
}

exit 1;
