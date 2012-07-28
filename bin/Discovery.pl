#!/usr/bin/env perl
#$Id: testDiscovery.pl,v 1.4 2012/06/18 02:57:37 cportman Exp $

use strict;
use Config::Auto;
use Log::Dispatch;
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
my $logger = Log::Dispatch->new(
    outputs => [
        [ 'Syslog', 'min_level' => 'info', 'ident' => 'PollerInput' ],
        [ 'Screen', 'min_level' => 'info', 'stdout' => 1, 'newline' => 1 ],
    ],
    callbacks => [ \&logPrependLevel, ]
);

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
                       where lastdiscovered is NULL--/;

my $sth = $dbh->prepare($getTargetsQuery);
my $res = $sth->execute();

my $module = 'Discovery';
my $output = 'DiscoveryDB';
my @jobList;

for my $targetRef ( @{ $sth->fetchall_arrayref( {} ) } ) {
    my $target    = $targetRef->{'target'};
    my $version   = $targetRef->{'snmpversion'};
    my $community = $targetRef->{'snmpcommunity'};

    push @jobList,
      {
        'module'      => $module,
        'output'      => $output,
        'methodInput' => {
            'target'    => $target,
            'version'   => $version,
            'community' => $community,
        },
      };

}

my $encodedJobs = encode_json( \@jobList );

if ( -p $fifo ) {
    open( my $fifoFH, '>', $fifo )
      or ( $logger->emergency(q/Could not open FIFO, can't continue./)
        and exit );

    print $fifoFH "$encodedJobs\n";

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

sub logPrependLevel {
    my %options = @_;

    my $message = $options{'message'};
    my $level   = uc( $options{'level'} );

    $message = "($level) $message"
      if $level;

    return $message;
}

exit 1;
