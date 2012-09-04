#!/usr/bin/env perl
#$Id: Graphite.pm,v 1.7 2012/06/07 03:43:34 cportman Exp $

package Jobsdoer::Output::Graphite;

use strict;
use warnings;

use lib '../../';

use Data::Dumper;
use AnyEvent::Graphite;
use Jobsdoer::Munge;

sub new {
    my $class  = ref $_[0] || $_[0];
    my $args   = $_[1];
    
    unless ( ref($args) and ref($args) eq 'ARRAY' ) {
		return;
	}
    
    my %selfHash;
    $selfHash{'resultset'} = $args;
    
    my $self = bless(\%selfHash, $class);
    
    return $self;
}

sub run {
    my $self = shift;
    my $resultset = $self->{'resultset'};
    
    #send to Graphite
    my $graphite = AnyEvent::Graphite->new(
        'host' => 'chrisp01.dev.optusnet.com.au',
        'port' => '2003',
    );
    
    for my $result ( @{$resultset} ) {
		#Simplify some vars
		my $target    = $result->{'target'};
		my $device    = $result->{'device'};
		my $category  = $result->{'category'};
		my $metric    = $result->{'metric'};
		my $value     = $result->{'value'} || 0;
		my $timestamp = $result->{'timestamp'};
		my $treelocat = $result->{'treeloc'};
		my $munge     = $result->{'munge'};
		
		#Manipulate the value if required
		
	    if ( $munge ) {
			my $munger = Jobsdoer::Munge->new($result);
			$value = $munger->$munge();
	    }
		
		#swap period chars for underscores
		$target =~ s|\.|_|g;
		$device =~ s|\.|_|g;
		
		my $metricName = $treelocat || 'Unknown';
		$target   and $metricName .= '.'.$target;
		$category and $metricName .= '.'.$category;
		$device   and $metricName .= '.'.$device;
		$metric   and $metricName .= '.'.$metric;
		
        #swap any space or '/' chars in the metric name with underscores.
	    $metricName   =~ s|[\s/]|_|g;

        #send to graphite
        $graphite->send($metricName, $value, $timestamp);
	}
	
	if ($graphite->{'conn'}) { $graphite->finish(); };
	
	return 1;
}

sub error{
    #dummy
    return;
}

1;
