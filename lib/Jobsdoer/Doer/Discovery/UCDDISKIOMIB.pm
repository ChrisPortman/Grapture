#!/usr/bin/env perl
# $Id: UCDDISKIOMIB.pm,v 1.2 2012/06/18 02:57:42 cportman Exp $

package Jobsdoer::Doer::Discovery::UCDDISKIOMIB;

use strict;
use warnings;

sub discover {
	
	[   #32 bit counters
	    {
			 'metric'      => 'IOCountReads',
   	         'mapbase'     => '1.3.6.1.4.1.2021.13.15.1.1.2',
	         'valbase'     => '1.3.6.1.4.1.2021.13.15.1.1.5',
	         'munge'       => 'perSecond',
	         'category'    => 'Storage',
	         'counterbits' => '32',
             'graphdef'    => 'LinuxDriveWRCount',
             'valtype'     => 'counter',
	    },
  	    {
			 'metric'      => 'IOCountWrites',
   	         'mapbase'     => '1.3.6.1.4.1.2021.13.15.1.1.2',
	         'valbase'     => '1.3.6.1.4.1.2021.13.15.1.1.6',
	         'munge'       => 'perSecond',
	         'category'    => 'Storage',
	         'counterbits' => '32',
             'graphdef'    => 'LinuxDriveWRCount',
             'valtype'     => 'counter',
	    },
  	    {
			 'metric'      => 'IOBytesRead',
   	         'mapbase'     => '1.3.6.1.4.1.2021.13.15.1.1.2',
	         'valbase'     => '1.3.6.1.4.1.2021.13.15.1.1.3',
	         'munge'       => 'perSecond',
	         'category'    => 'Storage',
	         'counterbits' => '32',
             'graphdef'    => 'LinuxDriveWRBytes',
             'valtype'     => 'counter',
	    },
  	    {
			 'metric'      => 'IOBytesWriten',
   	         'mapbase'     => '1.3.6.1.4.1.2021.13.15.1.1.2',
	         'valbase'     => '1.3.6.1.4.1.2021.13.15.1.1.4',
	         'munge'       => 'perSecond',
	         'category'    => 'Storage',
	         'counterbits' => '32',
	         'graphdef'    => 'LinuxDriveWRBytes',
             'valtype'     => 'counter',
	    },

        #64bit counters
  	    {
			 'metric'      => 'IOBytesRead',
   	         'mapbase'     => '1.3.6.1.4.1.2021.13.15.1.1.2',
	         'valbase'     => '1.3.6.1.4.1.2021.13.15.1.1.12',
	         'munge'       => 'perSecond',
	         'category'    => 'Storage',
	         'counterbits' => '64',
	         'graphdef'    => 'LinuxDriveWRBytes',
             'valtype'     => 'counter',
	    },
  	    {
			 'metric'      => 'IOBytesWriten',
   	         'mapbase'     => '1.3.6.1.4.1.2021.13.15.1.1.2',
	         'valbase'     => '1.3.6.1.4.1.2021.13.15.1.1.13',
	         'munge'       => 'perSecond',
	         'category'    => 'Storage',
	         'counterbits' => '64',
	         'graphdef'    => 'LinuxDriveWRBytes',
             'valtype'     => 'counter',
	    },
	];

}

1;
