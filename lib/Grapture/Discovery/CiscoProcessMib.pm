#!/bin/false
# $Id: CiscoProcessMib.pm,v 1.1 2012/06/18 02:57:41 cportman Exp $

package Grapture::Discovery::CiscoProcessMib;

use strict;
use warnings;

our $VERSION = (qw$Revision: 1.1 $)[1];

sub discover {
    [
        {    #CPU Usage
            'metric'     => 'CPU_Use_5sec',
            'valbase'    => '1.3.6.1.4.1.9.9.109.1.1.1.1.3.1',
            'graphdef'   => 'CiscoCpu',
            'valtype'    => 'gauge',
            'category'   => 'System',
            'device'     => 'CPU',
            'graphgroup' => 'CPULoad',
            'graphorder'  => 10,
        },
        {
            'metric'     => 'CPU_Use_1min',
            'valbase'    => '1.3.6.1.4.1.9.9.109.1.1.1.1.4.1',
            'graphdef'   => 'CiscoCpu',
            'valtype'    => 'gauge',
            'category'   => 'System',
            'device'     => 'CPU',
            'graphgroup' => 'CPULoad',
            'graphorder'  => 20,
        },
        {
            'metric'     => 'CPU_Use_5min',
            'valbase'    => '1.3.6.1.4.1.9.9.109.1.1.1.1.5.1',
            'graphdef'   => 'CiscoCpu',
            'valtype'    => 'gauge',
            'category'   => 'System',
            'device'     => 'CPU',
            'graphgroup' => 'CPULoad',
            'graphorder'  => 30,
        },
    ];

}

1;
