#!/usr/bin/env perl
# $Id: HostResoursesMib.pm,v 1.4 2012/06/18 02:57:42 cportman Exp $

package GH::Discovery::HOST_RESOURCES_MIB;

use strict;
use warnings;

our $VERSION = (qw$Revision: 1.4 $)[1];

sub discover {

    [
        {
            'metric'     => 'SpaceUsed',
            'mapbase'    => '1.3.6.1.2.1.25.2.3.1.3',
            'valbase'    => '1.3.6.1.2.1.25.2.3.1.6',
            'maxbase'    => '1.3.6.1.2.1.25.2.3.1.5',
            'category'   => 'Storage',
            'valtype'    => 'gauge',
            'graphorder' => 10,
            'filterSub'  => \&includeFilter,
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
