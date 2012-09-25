#!/bin/false

package Grapture::Common::JobsInterface;

use strict;
use Data::Dumper;
use Grapture::Common::Config;
use JSON::XS;
use Log::Any qw( $log );
use parent qw( Grapture );

sub new {
    my $class = shift;
    $class = ref $class || $class;
    
    my $config = Grapture::Common::Config->new();
    my $fifo   = $config->getSetting('MASTER_FIFO'); 
    
    unless ( -p $fifo ) {
        $log->critical('The FIFO does not exist.  Is the Job Distributor running?');
        return;
    }
    
    my %self = ( 'fifo' => $fifo );
    
    return bless(\%self, $class);
}

sub submitJobs {
    my $self = shift;
    my $jobs = ref $_[0] ? shift : \@_;
    my @validJobs;
    
    unless (ref $jobs eq 'ARRAY') {
        $log->error('Jobs should be an array ref for submitJobs');
        return;
    }
    
    #Check each job for required bits and pieces.
    for my $job ( @{$jobs} ) {
        # Each job must be a hash.
        unless ( ref $job eq 'HASH' ) {
            $log->error('Each job should be a hash ref for submitJobs');
            return;
        }
        
        # Make sure all these exist.
        for my $field ( qw( process output processOptions outputOptions ) ) {
            unless ( $job->{$field} ) {
                $log->error("Job missing $field field, skipping...");
                next;
            }
        }

        # These are hashes that contain stuff of interest to the doer and output
        # modules.  Let the modules validate the contents.
        for my $field ( qw( processOptions outputOptions ) ) {
            unless ( ref $job->{$field} eq 'HASH' ) {
                $log->error("Job $field field mush be a hash ref, skipping...");
                next;
            }
        }
        
        #set some defaults for optionals        
        $job->{'priority'} ||= 10;
        $job->{'waitTime'} ||= 300;
        
        push @validJobs, $job;
    }
    
    my $jobString = encode_json( \@validJobs ) or return;
    $self->_writeToFifo($jobString);
    
    return 1;
}

sub _writeToFifo {
    my $self   = shift;
    my $string = shift;
    my $fifo   = $self->{'fifo'};
    
    open( my $fifoFH, '>', $fifo )
      or ( $log->critical(q|Could not open FIFO, can't continue.|)
      and return );
    
    print $fifoFH $string;
    
    close $fifoFH;
    
    return 1;
}

1;
