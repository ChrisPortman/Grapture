#!/bin/false
# $Id: Ifmib.pm,v 1.7 2012/06/18 02:57:42 cportman Exp $

package Grapture::Discovery::IF_MIB;

use strict;
use warnings;

our $VERSION = (qw$Revision: 1.7 $)[1];

sub discover {

    #32 bit counters are added first, if 64 bit ones are available
    #they will overwrite the 32 bit ones and be used in preference.

    #Try to map the interfaces on ifName as its usually nicer.  If no
    #if name use ifDesc
    [
        #32 bit counters IfDesc
        {    #Interface Bits in
            'metric'  => 'BitsIn',
            'mapbase' => '1.3.6.1.2.1.2.2.1.2',
            'valbase' => '1.3.6.1.2.1.2.2.1.10',
            'maxbase'     => '1.3.6.1.2.1.2.2.1.5',
            'counterbits' => '32',
            'category'    => 'Interfaces',
            'valtype'     => 'derive',
            'graphgroup'  => 'InterfaceTraffic',
            'graphorder'  => 20,
            'conversion'  => 'bytesToBits',
            'filterSub'   => \&onlyUpWithPosInCounter,
        },
        {    #Interface Bits out
            'metric'  => 'BitsOut',
            'mapbase' => '1.3.6.1.2.1.2.2.1.2',
            'valbase' => '1.3.6.1.2.1.2.2.1.16',
            'maxbase'     => '1.3.6.1.2.1.2.2.1.5',
            'counterbits' => '32',
            'category'    => 'Interfaces',
            'valtype'     => 'derive',
            'graphgroup'  => 'InterfaceTraffic',
            'graphorder'  => 10,
            'conversion'  => 'bytesToBits',
            'filterSub'   => \&onlyUpWithPosInCounter,
        },

        {    #Interface Errors in
            'metric'      => 'ErrorsIn',
            'mapbase'     => '1.3.6.1.2.1.2.2.1.2',
            'valbase'     => '1.3.6.1.2.1.2.2.1.14',
            'counterbits' => '32',
            'category'    => 'Interfaces',
            'valtype'     => 'derive',
            'graphgroup'  => 'InterfaceErrors',
            'graphorder'  => 20,
            'filterSub'   => \&onlyUpWithPosInCounter,
        },
        {    #Interface Errors out
            'metric'      => 'ErrorsOut',
            'mapbase'     => '1.3.6.1.2.1.2.2.1.2',
            'valbase'     => '1.3.6.1.2.1.2.2.1.20',
            'counterbits' => '32',
            'category'    => 'Interfaces',
            'valtype'     => 'derive',
            'graphgroup'  => 'InterfaceErrors',
            'graphorder'  => 10,
            'filterSub'   => \&onlyUpWithPosInCounter,
        },

        #32 bit counters IfName
        {    #Interface Bits in
            'metric'  => 'BitsIn',
            'mapbase' => '1.3.6.1.2.1.31.1.1.1.1',
            'valbase' => '1.3.6.1.2.1.2.2.1.10',
            'maxbase'     => '1.3.6.1.2.1.2.2.1.5',
            'counterbits' => '32',
            'category'    => 'Interfaces',
            'valtype'     => 'derive',
            'graphgroup'  => 'InterfaceTraffic',
            'graphorder'  => 20,
            'conversion'  => 'bytesToBits',
            'filterSub'   => \&onlyUpWithPosInCounter,
        },
        {    #Interface Bits out
            'metric'  => 'BitsOut',
            'mapbase' => '1.3.6.1.2.1.31.1.1.1.1',
            'valbase' => '1.3.6.1.2.1.2.2.1.16',
            'maxbase'     => '1.3.6.1.2.1.2.2.1.5',
            'counterbits' => '32',
            'category'    => 'Interfaces',
            'valtype'     => 'derive',
            'graphgroup'  => 'InterfaceTraffic',
            'graphorder'  => 10,
            'conversion'  => 'bytesToBits',
            'filterSub'   => \&onlyUpWithPosInCounter,
        },

        {    #Interface Errors in
            'metric'      => 'ErrorsIn',
            'mapbase'     => '1.3.6.1.2.1.31.1.1.1.1',
            'valbase'     => '1.3.6.1.2.1.2.2.1.14',
            'counterbits' => '32',
            'category'    => 'Interfaces',
            'valtype'     => 'derive',
            'graphgroup'  => 'InterfaceErrors',
            'graphorder'  => 20,
            'filterSub'   => \&onlyUpWithPosInCounter,
        },
        {    #Interface Errors out
            'metric'      => 'ErrorsOut',
            'mapbase'     => '1.3.6.1.2.1.31.1.1.1.1',
            'valbase'     => '1.3.6.1.2.1.2.2.1.20',
            'counterbits' => '32',
            'category'    => 'Interfaces',
            'valtype'     => 'derive',
            'graphgroup'  => 'InterfaceErrors',
            'graphorder'  => 10,
            'filterSub'   => \&onlyUpWithPosInCounter,
        },

        #64 bit counters
        {    #Interface Bits in ifDesc
            'metric'  => 'BitsIn',
            'mapbase' => '1.3.6.1.2.1.2.2.1.2',
            'valbase' => '1.3.6.1.2.1.31.1.1.1.6',
            'maxbase'     => '1.3.6.1.2.1.2.2.1.5',
            'counterbits' => '64',
            'category'    => 'Interfaces',
            'valtype'     => 'derive',
            'graphgroup'  => 'InterfaceTraffic',
            'graphorder'  => 20,
            'conversion'  => 'bytesToBits',
            'filterSub'   => \&onlyUpWithPosInCounter,
        },
        {    #Interface Bits out
            'metric'  => 'BitsOut',
            'mapbase' => '1.3.6.1.2.1.2.2.1.2',
            'valbase' => '1.3.6.1.2.1.31.1.1.1.10',
            'maxbase'     => '1.3.6.1.2.1.2.2.1.5',
            'counterbits' => '64',
            'category'    => 'Interfaces',
            'valtype'     => 'derive',
            'graphgroup'  => 'InterfaceTraffic',
            'graphorder'  => 10,
            'conversion'  => 'bytesToBits',
            'filterSub'   => \&onlyUpWithPosInCounter,
        },

        {    #Interface Bits in ifName
            'metric'  => 'BitsIn',
            'mapbase' => '1.3.6.1.2.1.31.1.1.1.1',
            'valbase' => '1.3.6.1.2.1.31.1.1.1.6',
            'maxbase'     => '1.3.6.1.2.1.2.2.1.5',
            'counterbits' => '64',
            'category'    => 'Interfaces',
            'valtype'     => 'derive',
            'graphgroup'  => 'InterfaceTraffic',
            'graphorder'  => 20,
            'conversion'  => 'bytesToBits',
            'filterSub'   => \&onlyUpWithPosInCounter,
        },
        {    #Interface Bits out
            'metric'  => 'BitsOut',
            'mapbase' => '1.3.6.1.2.1.31.1.1.1.1',
            'valbase' => '1.3.6.1.2.1.31.1.1.1.10',
            'maxbase'     => '1.3.6.1.2.1.2.2.1.5',
            'counterbits' => '64',
            'category'    => 'Interfaces',
            'valtype'     => 'derive',
            'graphgroup'  => 'InterfaceTraffic',
            'graphorder'  => 10,
            'conversion'  => 'bytesToBits',
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

    return if $device =~ m/^(lo\d*$|unrouted|Loopback|Null)/;

    #get the opper status
    my $operStatus = $session->getValue('1.3.6.1.2.1.2.2.1.8.' . $devId);
    
    my $inCounter = $session->getValue('1.3.6.1.2.1.2.2.1.10.' . $devId);

    if ( $operStatus eq '1' and $inCounter =~ m/^[1-9]\d*$/ ) {
        return 1;
    }

    return;
}

1;
