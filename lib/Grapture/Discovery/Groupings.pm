#!/bin/false
# $Id: HostResoursesMib.pm,v 1.4 2012/06/18 02:57:42 cportman Exp $

# FIXME: this should probably implement something from a config file or from the database?
# FIXME: and should probably just be GH::Groupings

package Grapture::Discovery::Groupings;

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
        {
            'group'   => 'NetApp',
            'sysDesc' => [ qr/^\s*NetApp/i, ],
        },


        # A catch all!  Leave LAST!
        {
            'group'   => 'Unknown',
            'sysDesc' => [ qr/./, ],
        }

    ];

}

1;

#### Add unknown group to the DB!!!
