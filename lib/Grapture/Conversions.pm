#!/bin/false

=head1 NAME

Grapture::Conversions.pm

=head1 DESCRIPTION

This library is a collection of conversion functions that will apply 
some form of logic to the input to produce and return an output.

=head1 FUNCTIONS

=cut

package Grapture::Conversions;

use strict;
use warnings;
use Log::Any qw( $log );

=head2 bytesToBits

Requires one input which is a number of bytes, returns the corresponding
number of bits:

  my $bits = Grapture::Conversions::bytesToBits($bytes);
  
=cut

sub bytesToBits {
    my $class = shift if ref $_[0] eq __PACKAGE__;
    my $bytes = shift;
    
    if ($bytes and $bytes *= 1) {
         my $bits = $bytes * 8;
         $log->debug("Converted $bytes bytes to $bits bits");
         return $bits;
    }
    
    $log->error('Non-numeric value for bytes supplied to bytesToBits()');
    return;
}


1;
