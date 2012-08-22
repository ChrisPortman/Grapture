#!/usr/bin/env perl
# $Id: Ifmib.pm,v 1.7 2012/06/18 02:57:42 cportman Exp $

package Jobsdoer::Doer::Discovery::NETAPP_MIB;

use strict;
use warnings;

sub discover {

    [
        ########## INTERFACES #############
        
        #64 bit counters IfDesc
        {    #Interface Octets (~Bytes) in
            'metric'      => 'OctetsIn',
            'mapbase'     => '1.3.6.1.4.1.789.1.22.1.2.1.2',
            'valbase'     => '1.3.6.1.4.1.789.1.22.1.2.1.25',
           #'maxbase'     => '1.3.6.1.2.1.2.2.1.5',
            'counterbits' => '64',
            'category'    => 'Interfaces',
            'valtype'     => 'counter',
            'graphgroup'  => 'InterfaceTraffic',
            'graphorder'  => 20,
            'filterSub'   => \&onlyUpWithPosInCounter,
            'authoritive' => 1,
        },
        {    #Interface Octets (~Bytes) out
            'metric'      => 'OctetsOut',
            'mapbase'     => '1.3.6.1.4.1.789.1.22.1.2.1.2',
            'valbase'     => '1.3.6.1.4.1.789.1.22.1.2.1.31',
           #'maxbase'     => '1.3.6.1.2.1.2.2.1.5',
            'counterbits' => '64',
            'category'    => 'Interfaces',
            'valtype'     => 'counter',
            'graphgroup'  => 'InterfaceTraffic',
            'graphorder'  => 10,
            'filterSub'   => \&onlyUpWithPosInCounter,
            'authoritive' => 1,
        },

        {    #Interface Errors in
            'metric'      => 'ErrorsIn',
            'mapbase'     => '1.3.6.1.4.1.789.1.22.1.2.1.2',
            'valbase'     => '1.3.6.1.4.1.789.1.22.1.2.1.29',
            'counterbits' => '64',
            'category'    => 'Interfaces',
            'valtype'     => 'counter',
            'graphgroup'  => 'InterfaceErrors',
            'graphorder'  => 20,
            'filterSub'   => \&onlyUpWithPosInCounter,
            'authoritive' => 1,
        },
        {    #Interface Errors out
            'metric'      => 'ErrorsOut',
            'mapbase'     => '1.3.6.1.4.1.789.1.22.1.2.1.2',
            'valbase'     => '1.3.6.1.4.1.789.1.22.1.2.1.35',
            'counterbits' => '64',
            'category'    => 'Interfaces',
            'valtype'     => 'counter',
            'graphgroup'  => 'InterfaceErrors',
            'graphorder'  => 10,
            'filterSub'   => \&onlyUpWithPosInCounter,
            'authoritive' => 1,
        },
        
        ############ STORAGE ##############
        {    #Used space KB on volumes
            'metric'      => 'SpaceUsedPercent',
            'mapbase'     => '1.3.6.1.4.1.789.1.5.4.1.2',
            'valbase'     => '1.3.6.1.4.1.789.1.5.4.1.30',
            'maxbase'     => '1.3.6.1.4.1.789.1.5.4.1.29',
            'counterbits' => '64',
            'category'    => 'Volumes',
            'valtype'     => 'counter',
            'graphorder'  => 10,
            'filterSub'   => \&noSnapShots,
            'authoritive' => 1,
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
        '-varbindlist' => [ '1.3.6.1.4.1.789.1.22.1.2.1.25.' . $devId ], );
    $inCounter = $inCounter->{ '1.3.6.1.4.1.789.1.22.1.2.1.25.' . $devId };

    if ( $operStatus eq '1' and $inCounter =~ m/^[1-9]\d*$/ ) {
        return 1;
    }

    return;
}

sub noSnapShots {
    my $devId   = shift;
    my $device  = shift;
    my $options = shift;
    my $session = shift;
    
    if ( $device =~ /\.snapshot$/ ) {
		return;
	}
	
	return 1;	
}	

1;
