#!/bin/false

package Grapture::Storage::RRDTool;

use strict;

use Grapture::Common::Config;
use IPC::ShareLite qw( :lock ); 
use Data::Dumper;
use RRDs;
use Sys::Hostname qw(hostname);
use Log::Any qw ( $log );

#Package config vars
my $rrdFileLoc;
my $rrdCached;
my $newGraphStart;
my $hostname = hostname();

#Just keep the machine and environment
$hostname =~ s/\.optus(?:net)?\.com\.au\s*$//i;

sub run {
    shift if    $_[0] eq __PACKAGE__ 
             || $_[0] eq 'Grapture::JobsProcessor::Modules::RRDTool';
    my $options = shift; #will be empty hash, we need none
    my $results = shift;
    
    
    my $target      = $results->{'target'}  || return;
    my $pollResults = $results->{'results'} || return;

    my %rrdUpdates;    #hash keyed on device.
    my $pollCount   = 0;
    my $targetCount = 1;

    my $config     = Grapture::Common::Config->new();
    $rrdFileLoc    = $config->getSetting('DIR_RRD') || return;
    $rrdCached     = $config->getSetting('RRD_BIND_ADDR');
    $newGraphStart = time - 300;
    $rrdFileLoc    =~ s|([^/])$|$1/|;

    #First rearrange the result hash so metrics per device are together.
    for my $result ( @{$pollResults} ) {

        #Simplify some vars
        my $category  = $result->{'category'};
        my $device    = $result->{'device'};
        my $metric    = $result->{'metric'};
        my $value     = $result->{'value'} || 0;
        my $timestamp = $result->{'timestamp'};
        my $valtype   = $result->{'valtype'};
        my $max       = $result->{'max'};

        unless ($target) {
            $target = $result->{'target'};
        }

        unless ( $rrdUpdates{$device} ) {
            $rrdUpdates{$device} = {};
        }

        $rrdUpdates{$device}->{$metric} = {
            'time'    => $timestamp,
            'value'   => $value,
            'valtype' => $valtype,
            'max'     => $max,
        };
        $rrdUpdates{$device}->{'category'} = $category;
    }

    #process each device and its metrics and do some manipulations
    for my $updDevice ( keys(%rrdUpdates) ) {
        my $category = delete $rrdUpdates{$updDevice}->{'category'};
        my $rrdFile = $rrdFileLoc.$target.'/';
        unless ( -d $rrdFile ) {
            $log->debug("Creating dir $rrdFile for $target");
            unless ( mkdir $rrdFile ) {
                $log->error('Could not create dir '.$rrdFile.': '.$!);
                return;
            }
        }

        # Add the category to RRD file location if applicable
        if ($category) {
            $rrdFile .= $category . '/';
            unless ( -d $rrdFile ) {
                $log->debug("Creating dir $rrdFile for $category");
                unless ( mkdir $rrdFile ) {
                    $log->error('Could not create dir '.$rrdFile.': '.$!);
                    return;
                }
            }
        }
        else {
            return;
        }

        # Add the device to the file directory
        if ($updDevice) {
            my $devFileName = $updDevice;
            $devFileName =~ s|\/|_SLSH_|g;

            $rrdFile .= $devFileName . '/';
            unless ( -d $rrdFile ) {
                $log->debug("Creating dir $rrdFile for $updDevice");
                unless ( mkdir $rrdFile ) {
                    $log->error('Could not create dir '.$rrdFile.': '.$!);
                    return;
                }
            }
        }
        else {
            return;
        }

        for my $updMetric ( keys( %{ $rrdUpdates{$updDevice} } ) ) {

            #finish the rrd file name and location with <metric>.rrd
            my $devFileName = $updMetric . '.rrd';
            $devFileName =~ s|\/|_SLSH_|g;

            my $finalFileName = $rrdFile . $devFileName;

            my %update = %{ $rrdUpdates{$updDevice}->{$updMetric} };
            $update{'metric'} = $updMetric;

            _pushUpdate( $finalFileName, \%update );
            $pollCount ++;
        }
    }


    my %pollerPerformance = (
        'targets' => $targetCount,
        'metrics' => $pollCount
    );

    for my $metric ( keys %pollerPerformance ) {
        _updateStatsCounter($metric, $pollerPerformance{$metric});
    }
    
    return 1;
}

sub _pushUpdate {
    my $rrdFile    = shift;
    my $updateHash = shift;
    my $rrdObj;
    my @daemonSettings;

    #check that $updateHash is a hash ref.
    unless ( ref($updateHash) and ref($updateHash) eq 'HASH' ) {
        $log->error('RRDTool: The updateHash is not a valid format');
        return;
    }

    if ($rrdFile) {
        unless ( -f $rrdFile ) {
            $log->debug( "Creating file $rrdFile for" );
            _createRrd( $rrdFile, $updateHash )
              or return;
        }
    }

    #if using daemon use a relative path (remove the RRD base location
    if ( $rrdCached ) {
        $rrdFile =~ s/^$rrdFileLoc//;
        @daemonSettings = ( '--daemon', $rrdCached );
    }

    $log->debug("RRDTool: Sending updates to $rrdFile: ".$updateHash->{'value'});
    RRDs::update( $rrdFile, $updateHash->{'time'} . ':' . $updateHash->{'value'},
        @daemonSettings );

    my $error = RRDs::error;
    if ($error) {
        $log->error('Could not update '.$rrdFile.': '.$error);
        return;
    }

    return 1;
}

sub _createRrd {
    my $file       = shift;
    my $updateHash = shift;

    my @datasources;
    my @rras;

    my $ds   = $updateHash->{'metric'};
    my $type = uc( $updateHash->{'valtype'} );
    my $max  = $updateHash->{'valmax'} || 'U';
    my $min  = $updateHash->{'valmin'} || 'U';

    push @datasources, ("DS:$ds:$type:600:$min:$max");

    push @rras, 'RRA:AVERAGE:0.5:1:2880';
    push @rras, 'RRA:AVERAGE:0.5:6:4320';
    push @rras, 'RRA:AVERAGE:0.5:24:8760';

    RRDs::create( $file, '--step', '300', '--start', $newGraphStart,
        @datasources, @rras, );
    my $error = RRDs::error;
    $log->error('Could not create RRD file: '.$error) if $error;

    return 1;
}

# Create an async process for upping the memory counters.  Async so that
# any blocking on accessing the memory will not delay the main process.
sub _updateStatsCounter {
    my $metric = shift;
    my $value  = shift;
    my $memVal;
    my $time;
    
    # Keys for the shared memory locations mapped to the metric names.
    # Keys may be numeric OR 4 character strings.
    my %metrics = (
        'targets' => 'targ',
        'metrics' => 'mets',
    );
    
    my %times = (
        'targets' => 'ttim',
        'metrics' => 'mtim',
    );
    
    $metrics{$metric} || return;
    
    #Auto reap dead children to avoid zombies
    local $SIG{'CHLD'} = 'IGNORE';
    
    # Fork a process to do the update creating the async behaviour
    my $pid = fork;
    
    if ($pid) {
        #true $pid is parent process
        return 1;
    } 
    elsif ( defined $pid ) {
        #Child has a 5 second max life span.
        local $SIG{'ALRM'} = sub { $log->notice('A grapture stats alarm expired'); exit; };
        alarm 5;
        
        #$pid is 0 but defined = child process
        my $shareVal = IPC::ShareLite->new(
            -key => $metrics{$metric},
            -create => 'yes',
            -destroy => 'no',
        );
        
        my $shareTime = IPC::ShareLite->new(
            -key => $times{$metric},
            -create => 'yes',
            -destroy => 'no',
        );
        
        unless ($shareVal and $shareTime) {
            exit;
        }

        #update the metric value
        $shareVal->lock( LOCK_EX );
        
        $memVal  = $shareVal->fetch();
        $memVal += $value;
        
        $shareVal->store($memVal);
        
        #Check the time since the values were last sent to RRDtool
        #if > 30 secs, send an update and update the time.
        $shareTime->lock( LOCK_EX ); 
        $time = $shareTime->fetch();
        
        if (time - $time > 30) {
            $log->info("Sending metric $metric to RRD with value $memVal"); 
            #update the timre in mem
            $shareTime->store(time);
            $shareTime->unlock;
            
            #update the RRD.
            _storeGrapturePerformance($metric, $memVal);
        }
        else {
            $shareTime->unlock;
        }

        $shareVal->unlock;

        $log->info("$hostname has performed $memVal $metric operations");
        
        exit;
    }
    else {
        #undef $pid indicated for fail
        $log->error('Failed to update grapture stats');
    }
    
    return 1;
}

sub _storeGrapturePerformance {
    my $metric = shift || return;
    my $value  = shift || return;

    my $rrdPath = $rrdFileLoc.'Grapture/'.$hostname.'/';

    unless ( -d $rrdPath ) {
        my $dir = '/';
        for ( split m|/|, $rrdPath ) {
            next unless $_;
            $dir .= $_.'/';
            unless (-d $dir ) {
                unless ( mkdir $dir ) {
                    $log->error('Could not create '.$dir.': '.$!);
                    return;
                }
            }
        }
    }
    
    my $rrdFile = $rrdPath.$metric.'.rrd';

    my %update = (
        'metric'  => $metric,
        'time'    => time,
        'value'   => $value,
        'valtype' => 'DERIVE',
        'valmin'  => '0',
    );

    _pushUpdate($rrdFile, \%update);

    return 1;
}

1;
