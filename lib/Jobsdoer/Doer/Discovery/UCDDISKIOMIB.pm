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
	         'category'    => 'Storage',
	         'counterbits' => '32',
             'valtype'     => 'counter',
             'graphgroup'  => 'StorageIOCount',
	    },
  	    {
			 'metric'      => 'IOCountWrites',
   	         'mapbase'     => '1.3.6.1.4.1.2021.13.15.1.1.2',
	         'valbase'     => '1.3.6.1.4.1.2021.13.15.1.1.6',
	         'category'    => 'Storage',
	         'counterbits' => '32',
             'valtype'     => 'counter',
             'graphgroup'  => 'StorageIOCount',
	    },
  	    {
			 'metric'      => 'IOBytesRead',
   	         'mapbase'     => '1.3.6.1.4.1.2021.13.15.1.1.2',
	         'valbase'     => '1.3.6.1.4.1.2021.13.15.1.1.3',
	         'category'    => 'Storage',
	         'counterbits' => '32',
             'valtype'     => 'counter',
             'graphgroup'  => 'StorageIOBytes',
	    },
  	    {
			 'metric'      => 'IOBytesWriten',
   	         'mapbase'     => '1.3.6.1.4.1.2021.13.15.1.1.2',
	         'valbase'     => '1.3.6.1.4.1.2021.13.15.1.1.4',
	         'category'    => 'Storage',
	         'counterbits' => '32',
             'valtype'     => 'counter',
             'graphgroup'  => 'StorageIOBytes',
	    },

        #64bit counters
  	    {
			 'metric'      => 'IOBytesRead',
   	         'mapbase'     => '1.3.6.1.4.1.2021.13.15.1.1.2',
	         'valbase'     => '1.3.6.1.4.1.2021.13.15.1.1.12',
	         'category'    => 'Storage',
	         'counterbits' => '64',
             'valtype'     => 'counter',
             'graphgroup'  => 'StorageIOBytes',
	    },
  	    {
			 'metric'      => 'IOBytesWriten',
   	         'mapbase'     => '1.3.6.1.4.1.2021.13.15.1.1.2',
	         'valbase'     => '1.3.6.1.4.1.2021.13.15.1.1.13',
	         'category'    => 'Storage',
	         'counterbits' => '64',
             'valtype'     => 'counter',
             'graphgroup'  => 'StorageIOBytes',
	    },
	];

}

1;
