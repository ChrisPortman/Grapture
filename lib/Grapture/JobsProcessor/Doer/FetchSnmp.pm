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
    use Data::Dumper;
    use Grapture::FetchSnmp;
    use Log::Any qw ( $log );

    # Use BEGIN to clear the module from %ISA so that it can be reloaded
    # and include any changes.
    BEGIN {
        my @catchChangesIn = ( 'Grapture::FetchSnmp' );
        
        for my $prerec ( @catchChangesIn ){
            $prerec .= '.pm';
            $prerec =~ s|::|/|g;
            
            if ( $INC{ $prerec } ) {
                delete $INC{ $prerec };
            }
        }
    }

    sub new {
        #dummy new until new() is deprecated.
        my $class = shift;
        my %dummy;
        return bless(\%dummy, $class);
    }
    
    sub run {
        my $self = shift;
        my $params = shift;
        
        unless ( $params and ref( $params ) eq 'HASH' ) {
            $log->error('FetchSnmp->run() expects a hash ref');
            return;
        }
    
        my %maps;
        my %polls;
        my $target;
        my $version;
        my $community;
    
        $target    = $params->{'target'};
        $version   = $params->{'version'};
        $community = $params->{'community'};

        #build a deduped list of map table oids. and a hash of metrics
        for my $job ( @{ $params->{'metrics'} } ) {
            #if there is no device, then the metric must be a system wide one
            # eg Load
            $job->{'device'} ||= 'System';

            #stash the mapbase into the maps hash so that they are deduped
            if ( $job->{'mapbase'} ) {
                $maps{ $job->{'mapbase'} } = 1;
            }
        }

        # Create a grapture SNMP object.        
        my $GraptureSnmp = Grapture::FetchSnmp->new( 
            { 
                'target' => $target,
                'version' => $version,
                'community' => $community,
            }
        ) || ( $log->error('Failed to create Grapture::Snmp object') and return);
            
        #Build a hash for the Grapture::FetchSnmp->pollProcess() process.
        my %jobParams = (
            'maps'      => [ keys(%maps) ],  #only the keys are important
            'polls'     => $params->{'metrics'},
        );
        
        #build the result data structure
        my %result;
        $result{'target'}  = $target;
        $result{'results'} = $GraptureSnmp->pollProcess(\%jobParams) 
          || ( $log->error('Grapture::Snmp did not return a result') and return);
        
        return wantarray ? %result : \%result;
    }

    sub error {
        #dummy shile OO is depricated.
        return;
    }

1;
