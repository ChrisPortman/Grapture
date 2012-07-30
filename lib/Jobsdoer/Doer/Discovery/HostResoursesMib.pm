#!/usr/bin/env perl
# $Id: HostResoursesMib.pm,v 1.4 2012/06/18 02:57:42 cportman Exp $

package Jobsdoer::Doer::Discovery::HostResoursesMib;

use strict;
use warnings;

sub discover {

	[
	    {
			 'metric'      => 'SpaceUsed',
   	         'mapbase'     => '1.3.6.1.2.1.25.2.3.1.3',
	         'valbase'     => '1.3.6.1.2.1.25.2.3.1.6',
	         'maxbase'     => '1.3.6.1.2.1.25.2.3.1.5',
	         'category'    => 'Storage',
             'valtype'     => 'gauge',
             'filterSub'   => \&includeFilter,
		},
    ];

}

sub includeFilter {
    my $devId   = shift;
    my $device  = shift;
    my $options = shift;
    my $session = shift;

    if ( $device =~ m|^/| ) {
		return 1;
	}
    
    return;
}

1;
