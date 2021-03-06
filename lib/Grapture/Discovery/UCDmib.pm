#!/bin/false
# $Id: UCDmib.pm,v 1.3 2012/06/18 02:57:42 cportman Exp $

package Grapture::Discovery::UCDmib;

use strict;
use warnings;

our $VERSION = (qw$Revision: 1.3 $)[1];

sub discover {
    my $snmpOptions = shift;

    [
        {
            'metric'     => 'Load-1',
            'valbase'    => '1.3.6.1.4.1.2021.10.1.3.1',
            'valtype'    => 'gauge',
            'category'   => 'System',
            'device'     => 'CPU',
            'graphgroup' => 'CPULoad',
            'graphorder' => 10,
        },
        {
            'metric'     => 'Load-5',
            'valbase'    => '1.3.6.1.4.1.2021.10.1.3.2',
            'valtype'    => 'gauge',
            'category'   => 'System',
            'device'     => 'CPU',
            'graphgroup' => 'CPULoad',
            'graphorder' => 20,
        },
        {
            'metric'     => 'Load-15',
            'valbase'    => '1.3.6.1.4.1.2021.10.1.3.3',
            'valtype'    => 'gauge',
            'category'   => 'System',
            'device'     => 'CPU',
            'graphgroup' => 'CPULoad',
            'graphorder' => 30,
        },
        {
            'metric'      => 'CpuUserTime',
            'valbase'     => '1.3.6.1.4.1.2021.11.50.0',
            'counterbits' => '32',
            'valtype'     => 'derive',
            'category'    => 'System',
            'device'      => 'CPU',
            'graphgroup'  => 'CPUUsage',
            'graphorder'  => 40,
        },
        {
            'metric'      => 'CpuSystemTime',
            'valbase'     => '1.3.6.1.4.1.2021.11.52.0',
            'counterbits' => '32',
            'valtype'     => 'derive',
            'category'    => 'System',
            'device'      => 'CPU',
            'graphgroup'  => 'CPUUsage',
            'graphorder'  => 30,
        },
        {
            'metric'      => 'CpuIdleTime',
            'valbase'     => '1.3.6.1.4.1.2021.11.53.0',
            'counterbits' => '32',
            'valtype'     => 'derive',
            'category'    => 'System',
            'device'      => 'CPU',
            'graphgroup'  => 'CPUUsage',
            'graphorder'  => 50,
        },
        {
            'metric'      => 'CpuWaitTime',
            'valbase'     => '1.3.6.1.4.1.2021.11.54.0',
            'counterbits' => '32',
            'valtype'     => 'derive',
            'category'    => 'System',
            'device'      => 'CPU',
            'graphgroup'  => 'CPUUsage',
            'graphorder'  => 20,
        },
        {
            'metric'      => 'CpuKernelTime',
            'valbase'     => '1.3.6.1.4.1.2021.11.55.0',
            'counterbits' => '32',
            'valtype'     => 'derive',
            'category'    => 'System',
            'device'      => 'CPU',
            'graphgroup'  => 'CPUUsage',
            'graphorder'  => 10,
        },
        {
            'metric'     => 'MemAvailableKB',
            'valbase'    => '1.3.6.1.4.1.2021.4.6.0',
            'maxbase'    => '1.3.6.1.4.1.2021.4.5.0',
            'valtype'    => 'gauge',
            'category'   => 'System',
            'device'     => 'Memory',
            'graphgroup' => 'MemoryUsage',
            'graphorder' => 30,
        },
        {
            'metric'     => 'MemCachedKB',
            'valbase'    => '1.3.6.1.4.1.2021.4.15.0',
            'maxbase'    => '1.3.6.1.4.1.2021.4.5.0',
            'valtype'    => 'gauge',
            'category'   => 'System',
            'device'     => 'Memory',
            'graphgroup' => 'MemoryUsage',
            'graphorder' => 20,
        },
        {
            'metric'     => 'MemBufferedKB',
            'valbase'    => '1.3.6.1.4.1.2021.4.14.0',
            'maxbase'    => '1.3.6.1.4.1.2021.4.5.0',
            'valtype'    => 'gauge',
            'category'   => 'System',
            'device'     => 'Memory',
            'graphgroup' => 'MemoryUsage',
            'graphorder' => 10,
        },
    ];

}

sub getMaxCpu {
    my $snmpOptions = shift;
    my $snmpobj = Grapture::FetchSnmp->new( $options );
    my %cpus    = $snmpobj->getTable('.1.3.6.1.2.1.25.3.3.1.1', 1);
    
    unless (%cpus) {
        return;
    }
    
    my $numberOfCpus = scalar( keys %cpus );
    
    if ( $numberOfCpus ) {
        return $numberOfCpus * 100;
    }
    
    return;
}
    
}

1;
