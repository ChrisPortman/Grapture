#!/usr/bin/env perl
# $Id: UCDmib.pm,v 1.3 2012/06/18 02:57:42 cportman Exp $

package Jobsdoer::Doer::Discovery::UCDmib;

use strict;
use warnings;

sub discover {
	
	[
	    {
			 'metric'      => 'Load-1',
	         'valbase'     => '1.3.6.1.4.1.2021.10.1.3.1',
	         'graphdef'    => 'LinuxCpu',
             'valtype'     => 'gauge',
             'category'    => 'System',
             'device'      => 'CPU',
		},
	    {
			 'metric'      => 'Load-5',
	         'valbase'     => '1.3.6.1.4.1.2021.10.1.3.2',
	         'graphdef'    => 'LinuxCpu',
             'valtype'     => 'gauge',
             'category'    => 'System',
             'device'      => 'CPU',
		},
	    {
			 'metric'      => 'Load-15',
	         'valbase'     => '1.3.6.1.4.1.2021.10.1.3.3',
	         'graphdef'    => 'LinuxCpu',
             'valtype'     => 'gauge',
             'category'    => 'System',
             'device'      => 'CPU',
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
		},
	    {
			 'metric'      => 'CpuIdleTime',
	         'valbase'     => '1.3.6.1.4.1.2021.11.53.0',
             'counterbits' => '32',
	         'munge'       => 'changeSinceLast',
	         'graphdef'    => 'LinuxCpu',
             'valtype'     => 'counter',
             'category'    => 'System',
             'device'      => 'CPU',
		},
	    {
			 'metric'      => 'CpuKernelTime',
	         'valbase'     => '1.3.6.1.4.1.2021.11.55.0',
             'counterbits' => '32',
	         'munge'       => 'changeSinceLast',
	         'graphdef'    => 'LinuxCpu',
             'valtype'     => 'counter',
             'category'    => 'System',
             'device'      => 'CPU',
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
		},
	    {
			 'metric'      => 'MemUsedKB',
	         'valbase'     => '1.3.6.1.4.1.2021.4.6.0',
	         'maxbase'     => '1.3.6.1.4.1.2021.4.5.0',
	         'munge'       => 'availToUsed',
	         'graphdef'    => 'LinuxMem',
             'valtype'     => 'gauge',
             'category'    => 'System',
             'device'      => 'Memory',
		},
	    {
			 'metric'      => 'MemCachedKB',
	         'valbase'     => '1.3.6.1.4.1.2021.4.15.0',
	         'graphdef'    => 'LinuxMem',
             'valtype'     => 'gauge',
             'category'    => 'System',
             'device'      => 'Memory',
		},
	    {
			 'metric'      => 'MemBufferedKB',
	         'valbase'     => '1.3.6.1.4.1.2021.4.14.0',
	         'graphdef'    => 'LinuxMem',
             'valtype'     => 'gauge',
             'category'    => 'System',
             'device'      => 'Memory',
		},
    ];

}




1;
