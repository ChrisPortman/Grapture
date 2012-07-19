#!/usr/bin/env perl
# $Id: HostResoursesMib.pm,v 1.4 2012/06/18 02:57:42 cportman Exp $

package Jobsdoer::Doer::Discovery::Groupings;

use strict;
use warnings;

sub discover {

	[
	    {
			 'group'   => 'Linux',
             'sysDesc' => [ qr/^\s*Linux/i, ],
		},
        {
			 'group'   => 'Routers',
             'sysDesc' => [ qr/^\s*Cisco/i, ],
		},

    ];

}


1;
