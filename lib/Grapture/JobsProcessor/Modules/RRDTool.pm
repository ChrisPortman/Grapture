#!/bin/false

=head1 NAME

  Grapture::JobsProcessor::Modules::RRDTool.pm
 
=head1 SYNOPSIS

  Stub module that makes Grapture::Storage::RRDTool available
  as an output module.

=head1 DESCRIPTION

  See Grapture::Storage::RRDTool

=cut 

package Grapture::JobsProcessor::Modules::RRDTool;

    use strict;
    use warnings;
    use Data::Dumper;
    
    use vars qw( $wraps );
    
    # Use BEGIN to clear the module from %ISA so that it can be reloaded
    # and include any changes.
    BEGIN {
        $wraps = 'Grapture::Storage::RRDTool';
        my $wrapFile = $wraps;
        $wrapFile .= '.pm';
        $wrapFile =~ s|::|/|g;
        
        if ( $INC{ $wrapFile } ) {
            delete $INC{ $wrapFile };
        }
    
        {
            no warnings 'redefine';
            eval "require $wraps";
        }

        our @ISA;
        push @ISA, $wraps;
        
    }

1;
