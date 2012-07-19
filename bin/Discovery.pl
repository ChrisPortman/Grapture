#!/usr/bin/env perl
#$Id: testDiscovery.pl,v 1.4 2012/06/18 02:57:37 cportman Exp $

use strict;
use JSON::XS;
use Data::Dumper;
use DBI;

my $fifo = '/tmp/pollermaster.cmd';

my $dbh = DBI->connect("DBI:Pg:dbname=grasshopper;host=127.0.0.1",
	                       "grasshopper",
	                       "hoppergrass",
	                       #{'RaiseError' => 1},
	                      );
	
if ( not $dbh ) { return; };

my $getTargetsQuery = 'select target, snmpversion, snmpcommunity
                       from targets
                       where lastdiscovered is NULL--';
                     
my $sth = $dbh->prepare($getTargetsQuery);
my $res = $sth->execute();

my $module = 'Discovery';
my $output = 'DiscoveryDB';
my @jobList;

for my $targetRef ( @{ $sth->fetchall_arrayref( {} ) } ) {
	my $target    = $targetRef->{'target'};
	my $version   = $targetRef->{'snmpversion'};
	my $community = $targetRef->{'snmpcommunity'};

    push @jobList, { 'module'        => $module,
                     'output'        => $output,
                     'methodInput'   => {
					                      'target'    => $target,
					                      'version'   => $version,
					                      'community' => $community,	 
					                    },
				   };
   
}

print Dumper(\@jobList);
my $encodedJobs = encode_json(\@jobList);

if ( -p $fifo ) {
	open (my $fifoFH, '>', $fifo)
      or die "Could not open FIFO, can't continue.\n";
    
    print $fifoFH "$encodedJobs\n";
    
    close $fifoFH;
}
else {
	print "FIFO not created, is the pollerMaster running?\n";
}

exit 1;



