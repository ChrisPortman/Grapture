#!/usr/bin/env perl
# $Id:$

package GH::Storage::RRDTool;

use strict;
use warnings;

use Data::Dumper;
use RRDs;
use Log::Any qw ( $log );

sub new {
    my $class = ref $_[0] || $_[0];
    my $data  = $_[1];
    my $opts  = $_[2];

    unless ( ref($data) and ref($data) eq 'ARRAY' ) {
        $log->error('Data not an array');
        return;
    }

    my %selfHash;
    $selfHash{'resultset'}     = $data;
    $selfHash{'rrdfileloc'}    = $opts->{'rrdfileloc'};
    $selfHash{'rrdcached'}     = $opts->{'rrdcached'};
    $selfHash{'newGraphStart'} = time - 300;

    unless ( $selfHash{'rrdfileloc'} ) {
        $log->error('RRD file location not specified');
        return;
    }

    $selfHash{'rrdfileloc'} =~ s|([^/])$|$1/|;

    my $self = bless( \%selfHash, $class );

    return $self;
}

sub run {
    my $self    = shift;
    my $results = $self->{'resultset'};

    my $target;        #A job is per target.
    my %rrdUpdates;    #hash keyed on device.

    #First rearrange the result hash so metrics per device are together.
    for my $result ( @{$results} ) {

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

        #Add the hostname as a dir to the RRD file location.
        if ($target) {
            $rrdFile = $self->{'rrdfileloc'} . $target . '/';
            unless ( -d $rrdFile ) {
                $log->debug("Creating dir $rrdFile for $updDevice");
                mkdir $rrdFile
                  or return;
            }
        }
        else {
            return;
        }

        # Add the category to RRD file location if applicable
        if ($category) {
            $rrdFile .= $category . '/';
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
        print "Arg not a hash\n";
        return;
    }

    if ($rrdFile) {
        unless ( -f $rrdFile ) {
            print "Creating file $rrdFile for\n";
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
    if ( $self->{'rrdcached'} ) {
        $rrdFile =~ s/^$self->{'rrdfileloc'}//;
        @daemonSettings = ( '--daemon', $self->{'rrdcached'} );
    }

    RRDs::update( $rrdFile, $updateHash->{'time'} . ':' . $values,
        @daemonSettings );

    my $error = RRDs::error;
    $log->error($error) if $error;

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

    RRDs::create( $file, '--step', '300', '--start', $self->{'newGraphStart'},
        @datasources, @rras, );
    my $error = RRDs::error;
    $log->error($error) if $error;

    return 1;
}

sub error {

    #dummy
    return;
}

1;
