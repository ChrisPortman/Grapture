#!/bin/false

=head1 NAME

  Grapture::JobsProcessor::Output::DiscoveryDB.pm
 
=head1 SYNOPSIS

  Stub module that makes Grapture::Storage::DiscoveryDB available
  as an output module.

=head1 DESCRIPTION

  See Grapture::Storage::DiscoveryDB

=cut 

package Grapture::JobsProcessor::Output::DiscoveryDB;

    use strict;
    use warnings;
    use vars qw( $wraps );
    
    # Use BEGIN to clear the module from %ISA so that it can be reloaded
    # and include any changes.
    BEGIN {
        $wraps = 'Grapture::Storage::DiscoveryDB';
        my $wrapFile = $wraps;
        $wrapFile .= '.pm';
        $wrapFile =~ s|::|/|g;
        
        if ( $INC{ $wrapFile } ) {
            delete $INC{ $wrapFile };
        }
    }
        
    our @ISA;
    
    {
        no warnings 'redefine';
        eval "require $wraps";
    }
    
    push @ISA, $wraps;
    
1;
