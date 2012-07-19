#!/usr/bin/env perl
# $Id: CiscoProcessMib.pm,v 1.1 2012/06/18 02:57:41 cportman Exp $

package Jobsdoer::Doer::Discovery::CiscoProcessMib;

use strict;
use warnings;

sub discover {
	[
	    {  #CPU Usage
			 'metric'      => 'CPU_Use_5sec',
	         'valbase'     => '1.3.6.1.4.1.9.9.109.1.1.1.1.3.1',
	         'graphdef'    => 'CiscoCpu',
             'valtype'     => 'gauge',
             'category'    => 'System',
             'device'      => 'CPU',
             'graphgroup'  => 'CPULoad',
		},
        {
			 'metric'      => 'CPU_Use_1min',
	         'valbase'     => '1.3.6.1.4.1.9.9.109.1.1.1.1.4.1',
	         'graphdef'    => 'CiscoCpu',
             'valtype'     => 'gauge',
             'category'    => 'System',
             'device'      => 'CPU',
             'graphgroup'  => 'CPULoad',
		},
        {
			 'metric'      => 'CPU_Use_5min',
	         'valbase'     => '1.3.6.1.4.1.9.9.109.1.1.1.1.5.1',
	         'graphdef'    => 'CiscoCpu',
             'valtype'     => 'gauge',
             'category'    => 'System',
             'device'      => 'CPU',
             'graphgroup'  => 'CPULoad',
		},
    ];
    
}

1;
