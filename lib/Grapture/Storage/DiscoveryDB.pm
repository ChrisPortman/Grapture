#!/usr/bin/env perl

package Grapture::Storage::DiscoveryDB;

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
        $log->error(
            'Output module requires results in the form of a ARRAY ref.');
        return;
    }

    unless ( $options and ref $options eq 'HASH' ) {
        unless ($options->{'dbhost'}
            and $options->{'dbname'}
            and $options->{'dbuser'}
            and $options->{'dbpass'} )
        {
            $log->error('DiscoverDB needs options containing DB details');
            return;
        }
    }

    my %selfHash;
    $selfHash{'resultset'} = $result;
    $selfHash{'dboptions'} = $options;

    my $self = bless( \%selfHash, $class );

    return $self;
}

sub run {
    my $self = shift;

    my $DBHOST = $self->{'dboptions'}->{'dbhost'};
    my $DBNAME = $self->{'dboptions'}->{'dbname'};
    my $DBUSER = $self->{'dboptions'}->{'dbuser'};
    my $DBPASS = $self->{'dboptions'}->{'dbpass'};

    my $dbh = DBI->connect(
        "DBI:Pg:dbname=$DBNAME;host=$DBHOST",
        $DBUSER, $DBPASS,
        {
            #'RaiseError' => 1,
            'PrintError' => 0,
        },
    );

    if ( not $dbh ) { return; }

    my $addMetricsQuery = 'INSERT INTO targetmetrics
	                       ( target,  device,      metric,  valbase,
	                         mapbase, counterbits, max,     category,
	                         module,  output,      valtype, graphgroup,
	                         graphorder, aggregate, enabled
	                       )
	                       VALUES ( ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ? ) --';

    my $updMetricsQuery = 'UPDATE targetmetrics SET
	                       valbase = ?,     mapbase = ?,
	                       counterbits = ?, max = ?,
	                       category = ?,    module = ?,
	                       output = ?,      valtype = ?,
	                       graphgroup = ?,  graphorder = ?,
	                       aggregate = ?,   enabled = ?
	                       WHERE
	                       target = ? AND device = ? AND metric = ? --';

    my $updTargetQuery = 'UPDATE targets
                           SET lastdiscovered = LOCALTIMESTAMP
                           WHERE target = ? --';

    my $sthaddmet = $dbh->prepare($addMetricsQuery);
    my $sthupdmet = $dbh->prepare($updMetricsQuery);
    my $sthupdtgt = $dbh->prepare($updTargetQuery);

    my %seenTargets;

    $log->info( Dumper($self->{'resultset'}) );

    for my $result ( @{$self->{'resultset'}} ) {

		if ( $result->{'target'} ) {
		    unless ( $seenTargets{ $result->{'target'} }) {
				$sthupdtgt->execute( $result->{'target'} );
				$seenTargets{ $result->{'target'} } = 1;
			}
		}

		$sthaddmet->execute(          $result->{'target'},
		    $result->{'device'},      $result->{'metric'},
		    $result->{'valbase'},     $result->{'mapbase'},
		    $result->{'counterbits'}, $result->{'max'},
		    $result->{'category'},    'FetchSnmp',
		    'RRDTool',                $result->{'valtype'},
		    $result->{'graphgroup'},  $result->{'graphorder'},
		    $result->{'aggregate'},   $result->{'enabled'}
		)
		or
		$sthupdmet->execute(         $result->{'valbase'},
	        $result->{'mapbase'},    $result->{'counterbits'}, 
	        $result->{'max'},        $result->{'category'},
	        'FetchSnmp',             'RRDTool',           
	        $result->{'valtype'},    $result->{'graphgroup'},
	        $result->{'graphorder'}, $result->{'aggregate'},
	        $result->{'enabled'},    $result->{'target'},
	        $result->{'device'},     $result->{'metric'},
	    );
	}

    return 1;
}

sub error {
    #dummy error sub for now
    return 1;
}

1;
