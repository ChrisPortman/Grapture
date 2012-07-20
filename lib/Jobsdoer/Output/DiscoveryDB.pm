#!/usr/bin/env perl

package Jobsdoer::Output::DiscoveryDB;

use strict;
use warnings;
use Data::Dumper;
use DBI;

sub _getConfig {
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

my $GHCONFIG = _getConfig( '../etc/grasshopper.cfg' );
my $DBHOST = $GHCONFIG->{'DB_HOSTNAME'};
my $DBNAME = $GHCONFIG->{'DB_DBNAME'};
my $DBUSER = $GHCONFIG->{'DB_USERNAME'};
my $DBPASS = $GHCONFIG->{'DB_PASSWORD'};

sub new {
    my $class  = ref $_[0] || $_[0];
    my $args   = $_[1];
    
    unless ( ref($args) and ref($args) eq 'ARRAY' ) {
		warn "Output module requires arguments in the form of a ARRAY ref.\n";
		return;
	}
    
    my %selfHash;
    $selfHash{'resultset'} = $args;
    
    my $self = bless(\%selfHash, $class);
    
    return $self;
}

sub run {
	my $self = shift;
	
    my $dbh = DBI->connect("DBI:Pg:dbname=$DBNAME;host=$DBHOST",
	                       $DBUSER,
	                       $DBPASS,
	                       {
							  #'RaiseError' => 1,
							   'PrintError' => 0,
						   },
	                      );
	
	if ( not $dbh ) { return; };
	
	my $addMetricsQuery = 'insert into targetmetrics 
	                       ( target,  device,      metric,  valbase,
	                         mapbase, counterbits, max,     category,
	                         module,  output,      valtype, graphgroup
	                       )
	                       VALUES ( ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ? )--';
	                       
	my $updMetricsQuery = 'update targetmetrics set
	                       valbase = ?,     mapbase = ?, 
	                       counterbits = ?, max = ?,
	                       category = ?,    module = ?,  
	                       output = ?,      valtype = ?
	                       graphgroup = ?
	                       where  
	                       target = ? and device = ? and metric = ? --';

    my $updTargetQuery  = 'update targets 
                           set lastdiscovered = LOCALTIMESTAMP,
                           groupname = ?
                           where target = ? --';
                           
	my $sthaddmet   = $dbh->prepare($addMetricsQuery);
	my $sthupdmet   = $dbh->prepare($updMetricsQuery);
	my $sthupdtgt   = $dbh->prepare($updTargetQuery);
	
	my %seenTargets;
	
	
	for my $result ( @{$self->{'resultset'}} ) {
		
		if ( $result->{'group'} and $result->{'target'}) {
		    unless ($seenTargets{ $result->{'target'} }) {
				$sthupdtgt->execute( $result->{'group'}, $result->{'target'} );
				$seenTargets{ $result->{'target'} } = 1;
			}
			next;
		}

		$sthaddmet->execute(          $result->{'target'},
		    $result->{'device'},      $result->{'metric'},
		    $result->{'valbase'},     $result->{'mapbase'},
		    $result->{'counterbits'}, $result->{'max'},
		    $result->{'category'},    'FetchSnmp',
		    'RRDTool',                $result->{'valtype'},
		    $result->{'graphgroup'}
		)
		or
		$sthupdmet->execute(      $result->{'valbase'},
	        $result->{'mapbase'}, $result->{'counterbits'}, 
	        $result->{'max'},     $result->{'category'},
	        'FetchSnmp',          'RRDTool',           
	        $result->{'valtype'}, $result->{'graphgroup'}, 
	        $result->{'target'},  $result->{'device'},  
	        $result->{'metric'},
	    );
	}

	return 1;
}

sub error {
	#dummy error sub for now
	return 1;
}


1;
