#!/usr/bin/env perl
#$Id: testDiscovery.pl,v 1.4 2012/06/18 02:57:37 cportman Exp $

use strict;
use JSON::XS;
use Data::Dumper;
use DBI;

my $fifo = '/tmp/pollermaster.cmd';

sub getConfig {
	my $cfgFile = shift;
	
	unless ($cfgFile and -f $cfgFile) {
		return;
	}
	
	open(my $fh, '<', $cfgFile)
	  or die "Could not open $cfgFile: $!\n";
	
	my %config = map  {
		             $_ =~ s/^\s+//;    #remove leading white space
		             $_ =~ s/\s+$//;    #remove trailing white space
		             $_ =~ s/\s*#.*$//; #remove trailing comments 
		             my ($opt, $val) = split(/\s*=\s*/, $_);
		             $opt => $val ;
				 }
	             grep { $_ !~ /(?:^\s*#)|(?:^\s*$)/ } #ignore comments and blanks
	             <$fh>;
	
	return \%config;
}


my $GHCONFIG = getConfig( '../etc/grasshopper.cfg' );
my $DBHOST = $GHCONFIG->{'DB_HOSTNAME'};
my $DBNAME = $GHCONFIG->{'DB_DBNAME'};
my $DBUSER = $GHCONFIG->{'DB_USERNAME'};
my $DBPASS = $GHCONFIG->{'DB_PASSWORD'};

my $dbh = DBI->connect("DBI:Pg:dbname=$DBNAME;host=$DBHOST",
	                       $DBUSER,
	                       $DBPASS,
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



