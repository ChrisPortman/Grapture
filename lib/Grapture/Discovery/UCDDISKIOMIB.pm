#!/bin/false
# $Id: UCDDISKIOMIB.pm,v 1.2 2012/06/18 02:57:42 cportman Exp $

package Grapture::Discovery::UCDDISKIOMIB;

use strict;
use warnings;

our $VERSION = (qw$Revision: 1.2 $)[1];

sub discover {
	
	[   #32 bit counters
	    {
			'metric'      => 'IOCountReads',
			'mapbase'     => '1.3.6.1.4.1.2021.13.15.1.1.2',
			'valbase'     => '1.3.6.1.4.1.2021.13.15.1.1.5',
			'category'    => 'Storage',
			'counterbits' => '32',
			'valtype'     => 'derive',
			'graphgroup'  => 'StorageIOCount',
            'graphorder'  => 10,
			'filterSub'   => \&filter,
	    },
  	    {
			'metric'      => 'IOCountWrites',
			'mapbase'     => '1.3.6.1.4.1.2021.13.15.1.1.2',
			'valbase'     => '1.3.6.1.4.1.2021.13.15.1.1.6',
			'category'    => 'Storage',
			'counterbits' => '32',
			'valtype'     => 'derive',
			'graphgroup'  => 'StorageIOCount',
            'graphorder'  => 20,
			'filterSub'   => \&filter,
	    },
  	    {
			'metric'      => 'IOBytesRead',
			'mapbase'     => '1.3.6.1.4.1.2021.13.15.1.1.2',
			'valbase'     => '1.3.6.1.4.1.2021.13.15.1.1.3',
			'category'    => 'Storage',
			'counterbits' => '32',
			'valtype'     => 'derive',
			'graphgroup'  => 'StorageIOBytes',
            'graphorder'  => 10,
            'filterSub'   => \&filter,
	    },
  	    {
			'metric'      => 'IOBytesWriten',
			'mapbase'     => '1.3.6.1.4.1.2021.13.15.1.1.2',
			'valbase'     => '1.3.6.1.4.1.2021.13.15.1.1.4',
			'category'    => 'Storage',
			'counterbits' => '32',
			'valtype'     => 'derive',
			'graphgroup'  => 'StorageIOBytes',
            'graphorder'  => 20,
            'filterSub'   => \&filter,
	    },

        #64bit counters
  	    {
			'metric'      => 'IOBytesRead',
			'mapbase'     => '1.3.6.1.4.1.2021.13.15.1.1.2',
			'valbase'     => '1.3.6.1.4.1.2021.13.15.1.1.12',
			'category'    => 'Storage',
			'counterbits' => '64',
			'valtype'     => 'derive',
			'graphgroup'  => 'StorageIOBytes',
            'graphorder'  => 10,
            'filterSub'   => \&filter,
	    },
  	    {
			'metric'      => 'IOBytesWriten',
			'mapbase'     => '1.3.6.1.4.1.2021.13.15.1.1.2',
			'valbase'     => '1.3.6.1.4.1.2021.13.15.1.1.13',
			'category'    => 'Storage',
			'counterbits' => '64',
			'valtype'     => 'derive',
			'graphgroup'  => 'StorageIOBytes',
            'graphorder'  => 20,
            'filterSub'   => \&filter,
	    },
	];

}

sub filter {
    my $devId   = shift;
    my $device  = shift;
    my $options = shift;
    my $session = shift;

    #Dont monitor any loop devices
    return if ( $device =~ /^loop/ );

    return 1;
}

1;
