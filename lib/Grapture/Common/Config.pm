#!/bin/false

package Grapture::Common::Config;

use strict;
use Data::Dumper;
use Config::Auto;
use Log::Any qw ( $log );
use parent qw( Grapture );

# Use a package var so that as config is accessed by different packages
# throughout the execution of the overall program it can be cached.
# Generally the program executable which would accept a cmd line opt
# would call new with the conf file, then any other Grapture packages
# or modules can call new with out it and get access to cached config.

my $CONF_FILE;
my %CONFIG;

sub new {
    my $class    = shift;
    my $confFile = shift;
    
    $class = ref $class || $class;

    my %selfHash;
    my $self = bless( \%selfHash, $class );

    if ( $confFile ) {
        unless ( -f $confFile ) {
            $log->error(
                'Could not load configuration, configuration file supplied but does not exist');
            return;
        }
        
        $CONF_FILE = $confFile;
        $self->readConfig() || return;
    }
    
    unless ( $CONF_FILE and %CONFIG ) {
        $log->error(
            'Could not load configuration, configuration file not yet supplied');
        return;
    }

    return $self;
}

sub readConfig {
    my $self = shift;
    
    return unless ( $CONF_FILE and -f $CONF_FILE );
    
    %CONFIG = Config::Auto::parse($CONF_FILE) || return;
    
    return 1;
}

sub getAllConfig {
    my $self   = shift;
    
    if (%CONFIG) {
        return wantarray ? %CONFIG : \%CONFIG;
    }
    
    return;
}

sub getSetting {
    my $self    = shift;
    my $setting = shift || return;
    
    if ( $CONFIG{$setting} ) {
        return $CONFIG{$setting};
    }
    
    return;
}
