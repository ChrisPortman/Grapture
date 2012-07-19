#!/usr/bin/env perl
# $Id: Ifmib.pm,v 1.7 2012/06/18 02:57:42 cportman Exp $

package Jobsdoer::Doer::Discovery::Ifmib;

use strict;
use warnings;

sub discover {
	#32 bit counters are added first, if 64 bit ones are available
	#they will overwrite the 32 bit ones and be used in preference.
	[
	    #32 bit counters
	    {
			 'metric'      => 'OctetsIn',
   	         'mapbase'     => '1.3.6.1.2.1.2.2.1.2',
	         'valbase'     => '1.3.6.1.2.1.2.2.1.10',
	         'maxbase'     => '1.3.6.1.2.1.2.2.1.5',
	         'counterbits' => '32',
	         'munge'       => 'perSecond',
	         'category'    => 'Interfaces',
             'exclregex'   => ['^lo$', '^unrouted', '^Loopback', '^Null'],
             'graphdef'    => 'IntOctsInOut',
             'valtype'     => 'counter',
		},
		{
			 'metric'      => 'OctetsOut',
   	         'mapbase'     => '1.3.6.1.2.1.2.2.1.2',
	         'valbase'     => '1.3.6.1.2.1.2.2.1.16',
	         'maxbase'     => '1.3.6.1.2.1.2.2.1.5',
	         'counterbits' => '32',
	         'munge'       => 'perSecond',
	         'category'    => 'Interfaces',
             'exclregex'   => ['^lo$', '^unrouted', '^Loopback', '^Null'],
             'graphdef'    => 'IntOctsInOut',
             'valtype'     => 'counter',
		},
		
		#64 bit counters
	    {
			 'metric'      => 'OctetsIn',
   	         'mapbase'     => '1.3.6.1.2.1.2.2.1.2',
	         'valbase'     => '1.3.6.1.2.1.31.1.1.1.6',
	         'maxbase'     => '1.3.6.1.2.1.2.2.1.5',
	         'counterbits' => '64',
	         'munge'       => 'perSecond',
	         'category'    => 'Interfaces',
             'exclregex'   => ['^lo$', '^unrouted', '^Loopback', '^Null'],
             'graphdef'    => 'IntOctsInOut',
             'valtype'     => 'counter',
		},
		{
			 'metric'      => 'OctetsOut',
   	         'mapbase'     => '1.3.6.1.2.1.2.2.1.2',
	         'valbase'     => '1.3.6.1.2.1.31.1.1.1.10',
	         'maxbase'     => '1.3.6.1.2.1.2.2.1.5',
	         'counterbits' => '64',
	         'munge'       => 'perSecond',
	         'category'    => 'Interfaces',
             'exclregex'   => ['^lo$', '^unrouted', '^Loopback', '^Null'],
             'graphdef'    => 'IntOctsInOut',
             'valtype'     => 'counter',
		},

	];
	
}

1;
