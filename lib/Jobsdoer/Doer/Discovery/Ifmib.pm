#!/usr/bin/env perl
# $Id: Ifmib.pm,v 1.7 2012/06/18 02:57:42 cportman Exp $

package Jobsdoer::Doer::Discovery::Ifmib;

use strict;
use warnings;

sub discover {

    #32 bit counters are added first, if 64 bit ones are available
    #they will overwrite the 32 bit ones and be used in preference.
    [
        #32 bit counters
        {    #Interface Octets (~Bytes) in
            'metric'      => 'OctetsIn',
            'mapbase'     => '1.3.6.1.2.1.31.1.1.1.1',
            'valbase'     => '1.3.6.1.2.1.2.2.1.10',
           #'maxbase'     => '1.3.6.1.2.1.2.2.1.5',
            'counterbits' => '32',
            'category'    => 'Interfaces',
            'valtype'     => 'counter',
            'graphgroup'  => 'InterfaceTraffic',
            'filterSub'   => \&onlyUpWithPosInCounter,
        },
        {    #Interface Octets (~Bytes) out
            'metric'      => 'OctetsOut',
            'mapbase'     => '1.3.6.1.2.1.31.1.1.1.1',
            'valbase'     => '1.3.6.1.2.1.2.2.1.16',
           #'maxbase'     => '1.3.6.1.2.1.2.2.1.5',
            'counterbits' => '32',
            'category'    => 'Interfaces',
            'valtype'     => 'counter',
            'graphgroup'  => 'InterfaceTraffic',
            'filterSub'   => \&onlyUpWithPosInCounter,
        },

        {    #Interface Errors in
            'metric'      => 'ErrorsIn',
            'mapbase'     => '1.3.6.1.2.1.31.1.1.1.1',
            'valbase'     => '1.3.6.1.2.1.2.2.1.14',
            'counterbits' => '32',
            'category'    => 'Interfaces',
            'valtype'     => 'counter',
            'graphgroup'  => 'InterfaceErrors',
            'filterSub'   => \&onlyUpWithPosInCounter,
        },
        {    #Interface Errors out
            'metric'      => 'ErrorsOut',
            'mapbase'     => '1.3.6.1.2.1.31.1.1.1.1',
            'valbase'     => '1.3.6.1.2.1.2.2.1.20',
            'counterbits' => '32',
            'category'    => 'Interfaces',
            'valtype'     => 'counter',
            'graphgroup'  => 'InterfaceErrors',
            'filterSub'   => \&onlyUpWithPosInCounter,
        },

        #64 bit counters
        {    #Interface Octets (~Bytes) in
            'metric'      => 'OctetsIn',
            'mapbase'     => '1.3.6.1.2.1.31.1.1.1.1',
            'valbase'     => '1.3.6.1.2.1.31.1.1.1.6',
           #'maxbase'     => '1.3.6.1.2.1.2.2.1.5',
            'counterbits' => '64',
            'category'    => 'Interfaces',
            'valtype'     => 'counter',
            'graphgroup'  => 'InterfaceTraffic',
            'filterSub'   => \&onlyUpWithPosInCounter,
        },
        {    #Interface Octets (~Bytes) out
            'metric'      => 'OctetsOut',
            'mapbase'     => '1.3.6.1.2.1.31.1.1.1.1',
            'valbase'     => '1.3.6.1.2.1.31.1.1.1.10',
           #'maxbase'     => '1.3.6.1.2.1.2.2.1.5',
            'counterbits' => '64',
            'category'    => 'Interfaces',
            'valtype'     => 'counter',
            'graphgroup'  => 'InterfaceTraffic',
            'filterSub'   => \&onlyUpWithPosInCounter,
        },
    ];
}

#metric defs can take a 'filterSub' option that should contain a
#reference to a sub routine that will be run to determine if the device
#should be enabled
sub onlyUpWithPosInCounter {
    my $devId   = shift;
    my $device  = shift;
    my $options = shift;
    my $session = shift;
    
    my @excludeRegexs = ( '^lo$', '^unrouted', '^Loopback', '^Null' );
    for (@excludeRegexs) {
		return if $device =~ $_;
	}

    #get the opper status
    my $operStatus = $session->get_request(
        '-varbindlist' => [ '1.3.6.1.2.1.2.2.1.8.' . $devId ], );
    $operStatus = $operStatus->{ '1.3.6.1.2.1.2.2.1.8.' . $devId };

    my $inCounter = $session->get_request(
        '-varbindlist' => [ '1.3.6.1.2.1.2.2.1.10.' . $devId ], );
    $inCounter = $inCounter->{ '1.3.6.1.2.1.2.2.1.10.' . $devId };

    if ( $operStatus eq '1' and $inCounter =~ m/^[1-9]\d*$/ ) {
        return 1;
    }

    return;
}

1;
