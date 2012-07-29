#!/usr/bin/env perl
# $Id: UCDmib.pm,v 1.3 2012/06/18 02:57:42 cportman Exp $

package Jobsdoer::Doer::Discovery::UCDmib;

use strict;
use warnings;

sub discover {

    [
        {
            'metric'     => 'Load-1',
            'valbase'    => '1.3.6.1.4.1.2021.10.1.3.1',
            'graphdef'   => 'LinuxCpu',
            'valtype'    => 'gauge',
            'category'   => 'System',
            'device'     => 'CPU',
            'graphgroup' => 'CPULoad',
        },
        {
            'metric'     => 'Load-5',
            'valbase'    => '1.3.6.1.4.1.2021.10.1.3.2',
            'graphdef'   => 'LinuxCpu',
            'valtype'    => 'gauge',
            'category'   => 'System',
            'device'     => 'CPU',
            'graphgroup' => 'CPULoad',
        },
        {
            'metric'     => 'Load-15',
            'valbase'    => '1.3.6.1.4.1.2021.10.1.3.3',
            'graphdef'   => 'LinuxCpu',
            'valtype'    => 'gauge',
            'category'   => 'System',
            'device'     => 'CPU',
            'graphgroup' => 'CPULoad',
        },
        {
            'metric'      => 'CpuUserTime',
            'valbase'     => '1.3.6.1.4.1.2021.11.50.0',
            'counterbits' => '32',
            'munge'       => 'changeSinceLast',
            'graphdef'    => 'LinuxCpu',
            'valtype'     => 'counter',
            'category'    => 'System',
            'device'      => 'CPU',
            'graphgroup'  => 'CPUUsage',
        },
        {
            'metric'      => 'CpuSystemTime',
            'valbase'     => '1.3.6.1.4.1.2021.11.52.0',
            'counterbits' => '32',
            'munge'       => 'changeSinceLast',
            'graphdef'    => 'LinuxCpu',
            'valtype'     => 'counter',
            'category'    => 'System',
            'device'      => 'CPU',
            'graphgroup'  => 'CPUUsage',
        },

        #Disabled.  I dont think it really adds anything to the info
        #~ {
        #~ 'metric'      => 'CpuIdleTime',
        #~ 'valbase'     => '1.3.6.1.4.1.2021.11.53.0',
        #~ 'counterbits' => '32',
        #~ 'munge'       => 'changeSinceLast',
        #~ 'graphdef'    => 'LinuxCpu',
        #~ 'valtype'     => 'counter',
        #~ 'category'    => 'System',
        #~ 'device'      => 'CPU',
        #~ 'graphgroup'  => 'CPUUsage',
        #~ },
        {
            'metric'      => 'CpuKernelTime',
            'valbase'     => '1.3.6.1.4.1.2021.11.55.0',
            'counterbits' => '32',
            'munge'       => 'changeSinceLast',
            'graphdef'    => 'LinuxCpu',
            'valtype'     => 'counter',
            'category'    => 'System',
            'device'      => 'CPU',
            'graphgroup'  => 'CPUUsage',
        },
        {
            'metric'      => 'CpuWaitTime',
            'valbase'     => '1.3.6.1.4.1.2021.11.54.0',
            'counterbits' => '32',
            'munge'       => 'changeSinceLast',
            'graphdef'    => 'LinuxCpu',
            'valtype'     => 'counter',
            'category'    => 'System',
            'device'      => 'CPU',
            'graphgroup'  => 'CPUUsage',
        },
        {
            'metric'     => 'MemUsedKB',
            'valbase'    => '1.3.6.1.4.1.2021.4.6.0',
            'maxbase'    => '1.3.6.1.4.1.2021.4.5.0',
            'munge'      => 'availToUsed',
            'graphdef'   => 'LinuxMem',
            'valtype'    => 'gauge',
            'category'   => 'System',
            'device'     => 'Memory',
            'graphgroup' => 'MemoryUsage',
        },
        {
            'metric'     => 'MemCachedKB',
            'valbase'    => '1.3.6.1.4.1.2021.4.15.0',
            'graphdef'   => 'LinuxMem',
            'valtype'    => 'gauge',
            'category'   => 'System',
            'device'     => 'Memory',
            'graphgroup' => 'CPUUsage',
            'graphgroup' => 'MemoryUsage',
        },
        {
            'metric'     => 'MemBufferedKB',
            'valbase'    => '1.3.6.1.4.1.2021.4.14.0',
            'graphdef'   => 'LinuxMem',
            'valtype'    => 'gauge',
            'category'   => 'System',
            'device'     => 'Memory',
            'graphgroup' => 'CPUUsage',
            'graphgroup' => 'MemoryUsage',
        },
    ];

}

1;
