#!/usr/bin/false

package Grapture::JobsProcessor::Modules::Alarms;

use strict;
use warnings;
use Data::Dumper;
use Grapture::Alarms;
use Log::Any qw ( $log );

# Use BEGIN to clear the module from %ISA so that it can be reloaded
# and include any changes.
BEGIN {
    my @catchChangesIn = ( 'Grapture::Storage::Memcached', 'Grapture::Alarms' );
    
    for my $prerec ( @catchChangesIn ){
        $prerec .= '.pm';
        $prerec =~ s|::|/|g;
        
        if ( $INC{ $prerec } ) {
            delete $INC{ $prerec };
        }
    }
}

sub run {
    shift if $_[0] eq __PACKAGE__;
    my $params = shift;
    my $result = shift;
    
    # No params means nothing to do
    return $result unless $params and ref $params eq 'ARRAY';
    return $result unless $params->[0];
    
    #Auto reap dead children to avoid zombies
    local $SIG{'CHLD'} = 'IGNORE';
    
    #Fork so the alarming can run in parallel, we dont need to get anything
    #back so why wait.  
    my $pid = fork;
    if ($pid) {
        #this is the parent, just return the result
        return $result;
    }
    elsif ( defined $pid ) {
        local $SIG{'ALRM'} = sub { $log->error("The alarms child process expired"); exit; };
        alarm 10;

        my %args = (
            'target' => $result->{'target'},
            'rules'  => $params,
            'metrics' => $result->{'results'},
        );
    
        my $alarms = Grapture::Alarms->new(\%args)
          or exit;
        
        $log->info("Child process running alarms");
        $alarms->checkAlarms();
        exit;
    }
    elsif (not defined $pid) {
        $log->error("There was an error forking off the alarm process");
    }
    
    return $result;
}

    
1
