#!/bin/false

package Grapture::Storage::Memcached;

use strict;

use Grapture::Common::Config;
use Cache::Memcached;
use Log::Any qw ( $log );

sub new {
    my $class = shift;
    $class = ref $class || $class;
    
    my $config  = Grapture::Common::Config->new();
    my $servers = $config->getSetting('MEMCACHED_SERVERS');
    my $port    = $config->getSetting('MEMCACHED_PORT');
    
    unless ($servers) {
        $log->error("No Memcached servers found in config.");
        return;
    }
    
    my @serverList;
    for my $server ( split(/\s*,\s*/, $servers) ) {
        unless ( $server =~ /:\d+$/ ) {
            #This server needs the port added
            next unless $port;
            $server .= ":$port";
        }
        push @serverList, $server;
    }
    
    unless (scalar @serverList) {
        $log->error("No valid servers found.  Ensure that either servers are specified in the form <server>:<port> or that the port is supplied using the MEMCACHED_PORT configuration option");
        return;
    }
    
    my $memcachedObj = Cache::Memcached->new(
        'servers' => \@serverList,
    );
    
    unless ($memcachedObj) {
        $log->error('Could not construct memcached object');
        return;
    }
    
    return $memcachedObj;
}

1;
