#!/bin/false

package Grapture::Storage::RRDTool;

use strict;

use Grapture::Common::Config;
use Data::Dumper;
use RRDs;
use Log::Any qw ( $log );

#Package config vars
my $rrdFileLoc;
my $rrdCached;
my $newGraphStart;

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
    
    my $config     = Grapture::Common::Config->new();
    $rrdFileLoc    = $config->getSetting('DIR_RRD') || return;
    $rrdCached     = $config->getSetting('RRD_BIND_ADDR');
    $newGraphStart = time - 300;
    $rrdFileLoc =~ s|([^/])$|$1/|;

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
        $rrdUpdates{$device}->{'category'} = $category,;
    }

    #process each device and its metrics and do some manipulations
    for my $updDevice ( keys(%rrdUpdates) ) {
        my $rrdFile;
        my $category = delete $rrdUpdates{$updDevice}->{'category'};

        # Add the category to RRD file location if applicable
        if ($category) {
            $rrdFile .= $rrdFileLoc.$target.'/'.$category . '/';
            unless ( -d $rrdFile ) {
                $log->debug("Creating dir $rrdFile for $updDevice");
                mkdir $rrdFile
                  or return;
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
                mkdir $rrdFile
                  or return;
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

            # create a hash structure that can be feed straight to rrd update
            my %update = (
                'values'  => {},
                'time'    => undef,
                'valtype' => {},
                'valmax'  => {},
            );

            my %updMetricHash = %{ $rrdUpdates{$updDevice}->{$updMetric} };

            $update{'values'}->{$updMetric}  = $updMetricHash{'value'};
            $update{'valtype'}->{$updMetric} = uc( $updMetricHash{'valtype'} );
            $update{'valmax'}->{$updMetric}  = $updMetricHash{'max'};
            $update{'time'}                  = $updMetricHash{'time'};

            $self->_pushUpdate( $finalFileName, \%update );
        }
    }

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

    my $values;
    for my $metric ( keys( %{ $updateHash->{'values'} } ) ) {
        $values .= $updateHash->{'values'}->{$metric} . ':';
    }

    $values =~ s/:$//;

    #if using daemon use a relative path (remove the RRD base location
    if ( $rrdCached ) {
        $rrdFile =~ s/^$rrdFileLoc//;
        @daemonSettings = ( '--daemon', $rrdCached );
    }

    $log->debug("RRDTool: Sending updates to $rrdFile");
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

    for my $ds ( keys( %{ $updateHash->{'values'} } ) ) {
        my $type = uc( $updateHash->{'valtype'}->{$ds} );
        my $max = $updateHash->{'valmax'}->{$ds} || 'U';

        push @datasources, ("DS:$ds:$type:600:U:$max");
    }

    push @rras, 'RRA:AVERAGE:0.5:1:2880';
    push @rras, 'RRA:AVERAGE:0.5:6:4320';
    push @rras, 'RRA:AVERAGE:0.5:24:8760';

    RRDs::create( $file, '--step', '300', '--start', $newGraphStart,
        @datasources, @rras, );
    my $error = RRDs::error;
    $log->error('Could not create RRD file: '.$error) if $error;

    return 1;
}

sub error {

    #dummy
    return;
}

1;
