#!/bin/false

package Grapture;

use strict;
use Log::Any qw ( $log );

sub error {
    my $self  = shift;
    my $error = shift;
    
    if ($error) {
        $self->{'error'} = $error;
        return $error;
    }
    elsif ( $self->{'error'} ) {
        $error = $self->{'error'};
        $self->{'error'} = undef;
        return $error;
    }
    
    return;
}
