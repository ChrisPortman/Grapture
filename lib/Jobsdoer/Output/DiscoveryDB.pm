#!/usr/bin/env perl

package Jobsdoer::Output::DiscoveryDB;

use strict;
use warnings;
use Data::Dumper;
use DBI;

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
	
	#print Dumper($self->{'resultset'});
	
	
    my $dbh = DBI->connect("DBI:Pg:dbname=monitoring;host=127.0.0.1",
	                       "monitoring",
	                       "12345",
	                       {
							  #'RaiseError' => 1,
							   'PrintError' => 0,
						   },
	                      );
	
	if ( not $dbh ) { return; };
	
	my $addMetricsQuery = 'insert into targetmetrics 
	                       ( target,  device,      metric, valbase,
	                         mapbase, counterbits, max,    category,
	                         module,  munge,       output, graphdef, valtype
	                       )
	                       VALUES ( ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ? )--';
	                       
	my $updMetricsQuery = 'update targetmetrics set
	                       valbase = ?,     mapbase = ?, 
	                       counterbits = ?, max = ?,
	                       category = ?,    module = ?,  
	                       munge = ?,       output = ?, 
	                       graphdef = ?,    valtype = ?
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
		    $result->{'munge'},       'Graphite',
		    $result->{'graphdef'},    $result->{'valtype'}
		)
		or
		$sthupdmet->execute(      $result->{'valbase'},
	        $result->{'mapbase'}, $result->{'counterbits'}, 
	        $result->{'max'},     $result->{'category'},
	        'FetchSnmp',          $result->{'munge'},
	        'Graphite',           $result->{'graphdef'},
	        $result->{'valtype'}, $result->{'target'},
	        $result->{'device'},  $result->{'metric'},
	    );
	}

	return 1;
}

sub error {
	#dummy error sub for now
	return 1;
}


1;
