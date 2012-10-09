#!/bin/false

package Grapture::Storage::RRDTool;

use strict;

use Grapture::Common::Config;
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

sub new {
    #Dummy till new() is deprecated
    my $class = ref $_[0] || $_[0];

    my %selfHash;

    my $self = bless( \%selfHash, $class );

    return $self;
}

sub run {
    my $self    = shift;
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

            $self->_pushUpdate( $finalFileName, \%update );
            $pollCount ++;
        }
    }

    $self->storeGrapturePerformance( 
        {
            'targets' => $targetCount,
            'metrics' => $pollCount
        }
    );
    
    return 1;
}

sub _pushUpdate {
    my $self       = shift;
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
            $self->_createRrd( $rrdFile, $updateHash )
              or return;
        }
    }

    my $values .= $updateHash->{'value'} . ':';;
    $values =~ s/:$//;

    #if using daemon use a relative path (remove the RRD base location
    if ( $rrdCached ) {
        $rrdFile =~ s/^$rrdFileLoc//;
        @daemonSettings = ( '--daemon', $rrdCached );
    }

    $log->debug("RRDTool: Sending updates to $rrdFile: $values");
    RRDs::update( $rrdFile, $updateHash->{'time'} . ':' . $values,
        @daemonSettings );

    my $error = RRDs::error;
    if ($error) {
        $log->error('Could not update '.$rrdFile.': '.$error);
        return;
    }

    return 1;
}

sub _createRrd {
    my $self       = shift;
    my $file       = shift;
    my $updateHash = shift;

    my @datasources;
    my @rras;

    my $ds   = $updateHash->{'metric'};
    my $type = uc( $updateHash->{'valtype'} );
    my $max  = $updateHash->{'valmax'} || 'U';

    push @datasources, ("DS:$ds:$type:600:U:$max");

    push @rras, 'RRA:AVERAGE:0.5:1:2880';
    push @rras, 'RRA:AVERAGE:0.5:6:4320';
    push @rras, 'RRA:AVERAGE:0.5:24:8760';

    RRDs::create( $file, '--step', '300', '--start', $newGraphStart,
        @datasources, @rras, );
    my $error = RRDs::error;
    $log->error('Could not create RRD file: '.$error) if $error;

    return 1;
}

sub storeGrapturePerformance {
    my $self = shift;
    my $perfData = ref $_[0] ? shift : \@_;

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

    my %vals = (
        'targetsPerSec' => $perfData->{'targets'},
        'metricsPerSec' => $perfData->{'metrics'},
    );

    for my $metric ( keys %vals ) {
        my $rrdFile .= $rrdPath.$metric.'.rrd';

        my %update;
        $update{'metric'}  = $metric;
        $update{'values'}  = $vals{$metric};
        $update{'valtype'} = 'ABSOLUTE';
        $update{'time'} = time;

        $self->_pushUpdate($rrdFile, \%update);
    }

    return 1;
}



sub error {

    #dummy
    return;
}

1;
