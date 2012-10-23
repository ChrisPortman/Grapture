#!/bin/false

=head1 NAME

  Grapture::JobsProcessor::Modules::DiscoveryDB.pm
 
=head1 SYNOPSIS

  Stub module that makes Grapture::Storage::DiscoveryDB available
  as an output module.

=head1 DESCRIPTION

  See Grapture::Storage::DiscoveryDB

=cut 

package Grapture::JobsProcessor::Modules::DiscoveryDB;

    use strict;
    use warnings;
    use Log::Any qw( $log );
    use vars qw( $wraps );
    use Grapture::Storage::MetaDB;
    
    sub run {
        shift if $_[0] eq __PACKAGE__;
        my $options = shift; #will be empty hash, we need none
        my $result  = shift;
        
        unless ( ref($result) and ref($result) eq 'ARRAY' ) {
            $log->error(
                'Output module requires results in the form of a ARRAY ref.');
            return;
        }
        
        my $metaDB = Grapture::Storage::MetaDB->new();
        $metaDB->storeDiscovery( $result ) or return;
        
        return 1;
    }
    
1;
