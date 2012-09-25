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
    use Log::Any qw( $log );
    use vars qw( $wraps );
    use Grapture::Storage::MetaDB;
    
    sub new {
        #Just a dummy.  Going to phase out the use of new() for plugables.
        my $class = shift;
        my %dummy;
        my $obj = bless \%dummy, $class;
        return $obj;
    }
    
    sub run {
        my $self = shift; #remove this when new() is deprecated and just functions
        my $result = shift;
        
        unless ( ref($result) and ref($result) eq 'ARRAY' ) {
            $log->error(
                'Output module requires results in the form of a ARRAY ref.');
            return;
        }
        
        my $metaDB = Grapture::Storage::MetaDB->new();
        $metaDB->storeDiscovery( $result ) or return;
        
        return 1;
    }
    
    sub error {
        #dummy error sub for now
        return 1;
    }


1;
