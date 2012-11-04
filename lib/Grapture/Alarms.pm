#!/usr/bin/false

package Grapture::Alarms;

use strict;
use warnings;
use Data::Dumper;
use Grapture::Storage::Memcached;
use Grapture::Storage::MetaDB;
use Data::RoundRobinArray;
use Log::Any qw ( $log );

my $reloadAlarms = 0;
$SIG{'HUP'} = sub { $reloadAlarms = 1; };

my %STATES = (
    1 => 'OK',
    2 => 'WARN',
    3 => 'CRITICAL',
);

sub new {
    my $class  = shift;
    my $params = ref $_[0] ? shift : \@_;
    
    my $rules   = $params->{'rules'};
    my $target  = $params->{'target'};
    my $metrics = $params->{'metrics'};
    
    unless ($rules and ref $rules eq 'ARRAY') {
        $log->error('Grapture::Alarms->new() requires rules as an array ref');
        return;
    }
    unless ($target) {
        $log->error('Grapture::Alarms->new() requires target');
        return;
    }
    unless ($metrics and ref $metrics eq 'ARRAY') {
        $log->error('Grapture::Alarms->new() requires metrics as an array ref');
        return;
    }
    
    my $memcache = Grapture::Storage::Memcached->new();
    my $memKey   = $target;
    $memcache->add($target, {}); #Will add if not exist.
    
    my %selfhash = (
        'target'  => $target,
        'rules'   => $rules,
        'metrics' => $metrics,
        'memObj'  => $memcache,
        'mem'     => $memcache->get($target),
    );

    my $obj = bless \%selfhash, ref $class || $class;
    
    return $obj;
}

sub checkAlarms {
    my $self = shift;
    
    my $target  = $self->{'target'};
    my $metrics = $self->{'metrics'};
    
    for my $metricResult ( @{$metrics} ) {
        $self->processRules($metricResult);
        
        my $device = $metricResult->{'device'};
        my $metric = $metricResult->{'metric'};
        next unless $self->{'mem'}->{$device}->{$metric}->{'rule'};
        next if $self->{'mem'}->{$device}->{$metric}->{'rule'}->{'disabled'};
        
        $self->storeResult($metricResult) or next;
        my $state = $self->checkAlarmThresh($metricResult) or next;
        
        if ( $state > 1 or
             ($self->{'mem'}->{$device}->{$metric}->{'state'} > 1
              and $state == 1 ) ) {
            
            $self->raiseAlarm($metricResult,$state);
        }
             
        $self->{'mem'}->{$device}->{$metric}->{'state'} = $state;
    }
    
    return 1;
}

sub processRules {
    my $self       = shift;
    my $metricHash = shift;
    
    if ($reloadAlarms) {
        $self->{'memObj'}->flush_all();
        $reloadAlarms = 0;
    }
    
    my $target = $metricHash->{'target'};
    my $device = $metricHash->{'device'};
    my $metric = $metricHash->{'metric'};
        
    if ( $self->{'mem'}->{$device}->{$metric} ) {
        return 1;
    }
    
    $self->{'mem'}->{$device} = {} unless $self->{'mem'}->{$device};
    $self->{'mem'}->{$device}->{$metric} = { 'state' => 1 };
    
    for my $rule ( @{$self->{'rules'}} ) {
        my $ruleTarget = $rule->{'target'};
        my $ruleDevice = $rule->{'device'};
        my $ruleMetric = $rule->{'metric'};
        
        $ruleTarget =~ s/\*/.*/; # * used like in a bash shell
        $ruleTarget =~ s/\./\./; # escape periods
        $ruleDevice =~ s/\*/.*/;
        $ruleDevice =~ s/\./\./;
        $ruleMetric =~ s/\*/.*/;
        $ruleMetric =~ s/\./\./;
        $ruleTarget = qr($ruleTarget);
        $ruleDevice = qr($ruleDevice);
        $ruleMetric = qr($ruleMetric);
        
        next unless (     $target =~ $ruleTarget
                      and $device =~ $ruleDevice
                      and $metric =~ $ruleMetric
                    );
                    
        #This rule matches
        $self->{'mem'}->{$device}->{$metric}->{'rule'} = $rule;

        last;
    }
    
    return 1;
}

sub storeResult {
    my $self       = shift;
    my $metricHash = shift;
    my $target     = $self->{'target'};
    my $device     = $metricHash->{'device'};
    my $metric     = $metricHash->{'metric'};
    my $value      = $metricHash->{'value'};
    my $rule       = $self->{'mem'}->{$device}->{$metric}->{'rule'};
    
    #If the thresholds are specified as something other than a raw comparison
    #e.g. percentage, translate the raw val to suit.
    my $threshType  = $rule->{'threshtype'};
    if ( lc $threshType eq 'percent' ) {
        unless ( $metricHash->{'max'} ) {
            $log->error("Alarm rule for $target/$device/$metric specifies val algorithm as percentage but metric has no max val");
            return;
        }
        $value = $value / $metricHash->{'max'} * 100;
    }

    unless ($self->{'mem'}->{$device}->{$metric}->{'values'}) {
        my $numValsToTrack = $rule->{'valspan'};
        unless ($numValsToTrack and $numValsToTrack =~ /^\d+$/) {
            $log->error("Alarm rule for $target/$device/$metric has invalid value for valspan - must be an integer");
            return;
        }
        my $rrArray = Data::RoundRobinArray->new($numValsToTrack);
        $self->{'mem'}->{$device}->{$metric}->{'values'} = $rrArray;
    }

    $self->{'mem'}->{$device}->{$metric}->{'values'}->add($metricHash->{'value'});
    
    return 1;
}

sub checkAlarmThresh {
    my $self       = shift;
    my $metricHash = shift;
    my $target     = $self->{'target'};
    my $device     = $metricHash->{'device'};
    my $metric     = $metricHash->{'metric'};
    my $rule       = $self->{'mem'}->{$device}->{$metric}->{'rule'};
    my $values     = $self->{'mem'}->{$device}->{$metric}->{'vaules'};
    
    my $comarisonMethod = $rule->{'comarisonMethod'} || 'average';
    my $comparisonVal;
    
    if (lc $comarisonMethod eq 'all_over') {
        #All the last <span number> of results are over
        $comparisonVal = $values->smallest();
    }
    elsif (lc $comarisonMethod eq 'majority_over') {
        #Most of the last <span number> of results are over
        my @sortedVals  = $values->sorted();
                
        # Get the index that hold the lowest val of the mojority
        my $majorityIdx = int( $#sortedVals / 2 ); 
        
        $comparisonVal = $sortedVals[$majorityIdx];
    }
    else {
        #The average of the last <span number> of results is over (default)
        $comparisonVal = $values->average();
    }
    
    my $state = 1;
    $state = 2 if $comparisonVal >= $rule->{'warn'};
    $state = 3 if $comparisonVal >= $rule->{'crit'};
    
    return $state;
}

sub raiseAlarm {
    my $self       = shift;
    my $metricHash = shift;
    my $state      = shift || return;
    my $target     = $self->{'target'};
    my $device     = $metricHash->{'device'};
    my $metric     = $metricHash->{'metric'};
    my $largest    = $self->{'mem'}->{$device}->{$metric}->{'values'}->largest();

    my $metaDB = Grapture::Storage::MetaDB->new();
    $metaDB->runFunction('update_alarm', $target, $device, $metric, $STATES{$state}, $largest)
      or $log->error("Failed to update alarm in database");

    if ( $self->{'mem'}->{$device}->{$metric}->{'rule'}->{'trapdest'} ) {
        #send a trap (TODO)
    }
    
    return 1;
}

1;
