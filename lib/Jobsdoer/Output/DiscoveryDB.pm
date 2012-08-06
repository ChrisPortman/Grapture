#!/usr/bin/env perl

package Jobsdoer::Output::DiscoveryDB;

use strict;
use warnings;
use Data::Dumper;
use DBI;
use Log::Any qw ( $log );

sub new {
    my $class   = shift;
    my $result  = shift;
    my $options = shift;
    
    $class = ref $class || $class;
        
    unless ( ref($result) and ref($result) eq 'ARRAY' ) {
		$log->error('Output module requires results in the form of a ARRAY ref.');
		return;
	}
	
	unless ($options and ref $options eq 'HASH') {
		unless (    $options->{'dbhost'} and $options->{'dbname'}
			    and $options->{'dbuser'} and $options->{'dbpass'} ) {
			$log->error('DiscoverDB needs options containing DB details');
			return;
		}
	}
    
    my %selfHash;
    $selfHash{'resultset'} = $result;
    $selfHash{'dboptions'} = $options;
    
    my $self = bless(\%selfHash, $class);
    
    return $self;
}

sub run {
	my $self = shift;

	my $DBHOST = $self->{'dboptions'}->{'dbhost'};
	my $DBNAME = $self->{'dboptions'}->{'dbname'};
	my $DBUSER = $self->{'dboptions'}->{'dbuser'};
	my $DBPASS = $self->{'dboptions'}->{'dbpass'};
	
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
	                         module,  output,      valtype, graphgroup,
	                         graphorder, enabled
	                       )
	                       VALUES ( ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ? )--';
	                       
	my $updMetricsQuery = 'update targetmetrics set
	                       valbase = ?,     mapbase = ?, 
	                       counterbits = ?, max = ?,
	                       category = ?,    module = ?,  
	                       output = ?,      valtype = ?,
	                       graphgroup = ?,  graphorder = ?,
	                       enabled = ?
	                       where  
	                       target = ? and device = ? and metric = ? --';

    my $updTargetQuery  = 'update targets 
                           set lastdiscovered = LOCALTIMESTAMP,
                           groupname = ?
                           where target = ? --';
                           
	my $sthaddmet = $dbh->prepare($addMetricsQuery);
	my $sthupdmet = $dbh->prepare($updMetricsQuery);
	my $sthupdtgt = $dbh->prepare($updTargetQuery);
	
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
		    $result->{'graphgroup'},  $result->{'graphorder'},
		    $result->{'enabled'}
		)
		or
		$sthupdmet->execute(         $result->{'valbase'},
	        $result->{'mapbase'},    $result->{'counterbits'}, 
	        $result->{'max'},        $result->{'category'},
	        'FetchSnmp',             'RRDTool',           
	        $result->{'valtype'},    $result->{'graphgroup'},
	        $result->{'graphorder'}, $result->{'enabled'}, 
	        $result->{'target'},     $result->{'device'},
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
