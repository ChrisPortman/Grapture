#!/usr/bin/env perl

use strict;
use lib '../lib';
use Getopt::Long;
use Config::Auto;
use Log::Dispatch::Config;
use JSON::XS;
use Data::Dumper;
use Grapture::Common::JobsInterface;
use Grapture::Common::Config;
use Grapture::Storage::MetaDB;

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

my $config       = Grapture::Common::Config->new($cfgfile);
my $metaDB       = Grapture::Storage::MetaDB->new();
my $jobInterface = Grapture::Common::JobsInterface->new();

my $module = 'Discovery';
my $output = 'DiscoveryDB';

my $targets = $metaDB->getTargetsForDiscovery();

my @jobList;

for my $targetRef ( @{ $targets } ) {
    my $target    = $targetRef->{'target'};
    my $version   = $targetRef->{'snmpversion'};
    my $community = $targetRef->{'snmpcommunity'};

    print "Adding job for $target\n";

    push @jobList,
      {
        'process'        => [
            {
                'name'    => $module,
                'options' => {
                    'target'    => $target,
                    'version'   => $version,
                    'community' => $community,
                },
            },
            {
                'name'    => $output,
                'options' => {},
            },
        ],
                    
        'priority'       => 100,
      };

    $logger->info("Queued discovery for $target");
}

unless (@jobList) {
    exit 1;
}

$jobInterface->submitJobs(\@jobList);

exit 1;
