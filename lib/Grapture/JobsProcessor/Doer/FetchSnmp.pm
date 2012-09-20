#!/bin/false

=head1 NAME

  Grapture::JobsProcessor::Doer::FetchSnmp.pm
 
=head1 SYNOPSIS

  Stub module that makes Grapture::FetchSnmp available as a doer module.

=head1 DESCRIPTION

  See Grapture::FetchSnmp

=cut 

package Grapture::JobsProcessor::Doer::FetchSnmp;

    use strict;
    use warnings;
    use vars qw( $wraps );
    
    # Use BEGIN to clear the module from %ISA so that it can be reloaded
    # and include any changes.
    BEGIN {
        $wraps = 'Grapture::FetchSnmp';
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
