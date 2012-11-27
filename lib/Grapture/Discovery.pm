#!/usr/bin/env perl

package Grapture::Discovery;

use strict;
use Grapture::FetchSnmp;
use Log::Any qw ( $log );
use Data::Dumper;

#Use plugable modules to allow on the fly expansion of functionality
use Module::Pluggable
  search_path => ['Grapture::Discovery'],
  require     => 1,
  sub_name    => 'discoverers',
  inner       => 0;

sub run {
    shift if    $_[0] eq __PACKAGE__
             || $_[0] eq 'Grapture::JobsProcessor::Modules::Discovery';
    my $options = shift;
    my @metrics;

    unless (ref $options 
        and $options->{'target'}
        and $options->{'version'}
        and $options->{'community'} )
    {
        die "Options must include 'target', 'version' and 'community'\n";
    }
    
    my @discoveryMods = discoverers();
    my @metricDefs;

    for my $discoverer (@discoveryMods) {
        my $params;
        eval { $params = $discoverer->discover(); };
        if ($@) {
            warn
"An error occured trying to run $discoverer, its being ignored: $@\n";
            next;
        }

        if ( ref $params eq 'ARRAY' ) {
            push @metricDefs, @{$params};

            #~ my $result = runDiscParams($options, $params);
#~ 
            #~ if ( ref $result eq 'ARRAY' ) {
                #~ push @metrics, @{$result};
            #~ }
            #~ elsif ( not defined $result ) {
                #~ last;
            #~ }
        }
    }
    
    my @metrics = discoverMetrics($options, \@metricDefs);

    return wantarray ? @metrics : \@metrics;
}

sub discoverMetrics {
    my $targetOptions = shift;
    my $metricDefs    = ref $_[0] ? shift : \@_;
    
    ref $metricDefs eq 'ARRAY' or return;

    my $target  = $targetOptions->{'target'};
    my $session = Grapture::FetchSnmp->new( $options ) or return;
    
    #Try getting the sysdesc to test reachablity.
    my $sysDesc = $session->getValue( '.1.3.6.1.2.1.1.1.0', 1 ) or return;
    
    my %authoritives;
    my %enabledCache;
    my @discoveredDeviceMetrics;
    
    METRIC:
    for my $metricDef ( @{$metricDefs} ) {
        # If we already have an authoritive def for this metric, skip
        next if $authoritives{ $metricDef->{'metric'} };
        
        #test that the valbase is valid on this target
        $session->getValue( $metricDef->{'valbase'}, 1 ) or next;

        #We have some work to do...
        #Simplify access to various details for here on...
        my $metric      = $metricDef->{'metric'};
        my $valOid      = $metricDef->{'valbase'};
        my $mapOid      = $metricDef->{'mapbase'};
        my $max         = $metricDef->{'maxbase'};
        my $category    = $metricDef->{'category'};
        my $graphgroup  = $metricDef->{'graphgroup'};
        my $graphorder  = $metricDef->{'graphorder'};
        my $counterbits = $metricDef->{'counterbits'};
        my $conversion  = $metricDef->{'conversion'};
        my $filtersub   = $metricDef->{'filtersub'};
        my $valtype     = $metricDef->{'valtype'};
        my $aggregate   = $metricDef->{'aggregate'};
        my $authoritive = $metricDef->{'authoritive'};
        
        #Get the map table if applicable
        my %maptable = $session->getMapping( $mapOid, 1 );
        
        # Build a list of devices (should be the keys of %maptable OR
        # the device key in the metric def.  It would be wierd to have both
        my @devices = ( keys(%maptable), $metricDef->{'device'} );

        DEVICE:
        for my $device ( @devices ) {
            #work out if this device should be included
            my %discMetricDetails = ( 'enabled' => 1 );
            if ($filtersub and ref $filtersub eq 'CODE') {
                if ( defined $enabledCache{$device} ) {
                    $discMetricDetails{'enabled'} = $enabledCache{$device};
                }
                else {
                    my $enable;
                    eval {
                        $enable = $filtersub->(
                            $maptable{$device},
                            $device,
                            $metricDef,
                            $session
                        );
                    };
                    if ($@) {
                        $log->error("Filter sub for $device/$metric died. Device will be enabled for monitoring");
                        $enable = 1;
                    }
                    $discMetricDetails{'enabled'} = $enable || 0;
                }
            }
            
            #Try to work out the max val.  It can be:
            # - an oid that has to be fetched
            # - a scalar val to be used verbatim
            # - a sub ref to compute it.
            if ( $max ) {
                if ( ref $max and ref $max eq 'CODE' ){
                    #Run the code ref
                    my $realMax = $max->(
                        $maptable{$device},
                        $device,
                        $metricDef,
                        $session
                    );
                    if ($@) {
                        $log->error("Sub for max on $device/$metric died, there will be no max");
                        $max = undef;
                    }
                    $max = $realMax;
                }
                elsif ( $max =~ /^.?(?:\d+\.)+\d*$/ ) {
                    #This is an OID, fetch it.
                    $max = $session->getValue($max);
                }
                elsif ( $max =~ /^\d+(?:\.\d+)?$/ ) {
                    #This is a number in a scalar, just use it.
                }
                else {
                    #Dont know what to do with this
                    $log->error("The max ($max) for $device/$metric is not valid");
                    $max = undef;
                }
            }
            
            #Store everything
            
            #Mandatory
            $discMetricDetails{'target'}  = $target;
            $discMetricDetails{'metric'}  = $metric;
            $discMetricDetails{'valbase'} = $valbase;
            $discMetricDetails{'device'}  = $device;

            #Optionals
            $discMetricDetails{'mapbase'}     = $mapOid if $mapOid;
            $discMetricDetails{'category'}    = $category if $category;
            $discMetricDetails{'conversion'}  = $conversion if $conversion;
            $discMetricDetails{'counterbits'} = $counterbits if $counterbits;
            $discMetricDetails{'max'}         = $max if $max;
            $discMetricDetails{'valtype'}     = $valtype if $valtype;
            $discMetricDetails{'graphgroup'}  = $graphgroup if $graphgroup;
            $discMetricDetails{'graphorder'}  = $graphorder if $graphorder;
            $discMetricDetails{'aggregate'}   = $aggregate if $aggregate;
        
            push @discoveredDeviceMetrics, \%discMetricDetails;
        }
        
        if ($authoritive) {
            $authoritives{$metric} = 1;
        }
    }
    
    return wantarray ? @discoveredDeviceMetrics : \@discoveredDeviceMetrics;
    
}

sub runDiscParams {
    my $options = shift;
    my $params  = shift;
    
    print Dumper($options);
    
    return unless ref $options eq 'HASH';
    return unless ref $params  eq 'ARRAY';

    my $target  = $options->{'target'};
    my $sysDesc;
    my $group;

    my $session = Grapture::FetchSnmp->new( $options );
    return unless ( $target and $session );

    my @return;
    my %devStateCache;    #Cache the results of filterInclude for each Dev
    my %authoritives;     #store a record of authoritive metric defs so that
                          #they are not over written.

    #Get the sysdesc first.  It will be needed later.  Its also going to
    #a common requirenment of any device.  We also can use getting the
    #sysdesc as an availabiltiy test for the device
    unless ( $sysDesc = $session->getValue( '.1.3.6.1.2.1.1.1.0', 1 ) ){
        $log->error("$target did not respond");
        return;
    }

  METRIC:
    for my $metricDef ( @{$params} ) {
        next METRIC unless ref($metricDef) and ref($metricDef) eq 'HASH';

        my $metric = $metricDef->{'metric'}   || next METRIC;
        my $valbase = $metricDef->{'valbase'} || next METRIC;
        my $filterInclude;
        my $max;

        unless ( $metric =~ /^[a-zA-Z0-9_\-]{1,19}$/ ) {
            $log->error("Metric name $metric is invalid. Skipping");
            next METRIC;
        }

        if ( $authoritives{$metric} ) {
            #We already have a metric def that is authoritive. Skip
            next METRIC;
        }

        #look for a filter code ref
        if ( ref $metricDef->{'filterSub'} eq 'CODE' ) {
            $filterInclude = delete $metricDef->{'filterSub'};
        }
        else {
            $filterInclude = '';
        }

        if ( $metricDef->{'mapbase'} ) {
            my $map;
            my $vals;

            $log->debug("Getting values for $metric");
            $vals = $session->getTable( $valbase, 1 )
              || next METRIC;

            #we need to get the table for map base
            $log->debug("Getting mapbase for $metric");
            $map = $session->getMapping( $metricDef->{'mapbase'}, 1 )
              || next METRIC;

            $log->debug("Got the map table for $metric");

            if ( $metricDef->{'maxbase'} ) {
                $log->debug("Getting maxbase for $metric");
                $max = $session->getTable( $metricDef->{'maxbase'}, 1 )
                  || next METRIC;

         #knock the max keys down to just the index part of the OID (last digit)
                for my $key ( keys %{$max} ) {
                    my ($index) = $key =~ m/(\d+)$/;
                    $index or next METRIC;

                    $max->{$index} = delete $max->{$key};
                }

                $log->debug("Got the max table for $metric");
            }

          DEVICE:
            for my $device ( keys %{$map} ) {
                $log->debug("Checking for $metric on target device $device");

                #make sure that the device appears in the $vals for this
                #metric.  Not all devices in the map will have all the
                #metrics we've specified

                my $devId = $map->{$device};
                my $devValOid = $valbase . '.' . $devId;
                $devValOid =~ s/\.\././;

                unless ( defined $vals->{$devValOid} ) {
                    $log->debug("Metric not found on $target $device");
                    next DEVICE;
                }
                $log->debug("Found $metric on $target $device");

                my %deviceHash;

                $deviceHash{'enabled'} = 1;

                #If theres a filter sub run it now.
                if ($filterInclude) {
                    $log->debug(
                        "Checking to see if $device should be monitored");

                    if ( defined $devStateCache{$device} ) {
                        $deviceHash{'enabled'} = $devStateCache{$device};
                    }
                    else {
                        eval {
                            unless (
                                $filterInclude->(
                                    $devId, $device, $metricDef, $session
                                )
                              )
                            {
                                $deviceHash{'enabled'} = 0;
                            }
                            1;
                        };

                        if ($@) {

                            #If there was any error at all, force the device
                            #enabled
                            $log->error("Filter sub died: $@\n");
                            $deviceHash{'enabled'} = 1;
                        }
                        $devStateCache{$device} = $deviceHash{'enabled'};

                        if ( $deviceHash{'enabled'} ) {
                            $log->debug(
                                "Determined that $device SHOULD be monitored");
                        }
                        else {
                            $log->debug(
                                "Determined that $device SHOULD NOT be monitored"
                            );
                        }
                    }
                }

                #essentials for a mapped metric (tested earlier)
                $deviceHash{'target'}  = $target;
                $deviceHash{'metric'}  = $metric;
                $deviceHash{'device'}  = $device;
                $deviceHash{'valbase'} = $valbase;
                $deviceHash{'mapbase'} = $metricDef->{'mapbase'};

                #optionals
                $metricDef->{'category'}
                  and $deviceHash{'category'} = $metricDef->{'category'};
                $metricDef->{'conversion'}
                  and $deviceHash{'conversion'} = $metricDef->{'conversion'};
                $metricDef->{'counterbits'}
                  and $deviceHash{'counterbits'} = $metricDef->{'counterbits'};
                $metricDef->{'maxbase'}
                  and $deviceHash{'max'} = $max->{$devId};
                $metricDef->{'graphdef'}
                  and $deviceHash{'graphdef'} = $metricDef->{'graphdef'};
                $metricDef->{'valtype'}
                  and $deviceHash{'valtype'} = $metricDef->{'valtype'};
                $metricDef->{'graphgroup'}
                  and $deviceHash{'graphgroup'} = $metricDef->{'graphgroup'};
                $metricDef->{'aggregate'}
                  and $deviceHash{'aggregate'} = $metricDef->{'aggregate'};
                $deviceHash{'graphorder'} = $metricDef->{'graphorder'} || 10;

                push @return, \%deviceHash;
            }
        }
        else {
            #this is not a mapped device.
            my $device =
                $metricDef->{'device'}
              ? $metricDef->{'device'}
              : 'System';
            my %deviceHash;
            $deviceHash{'enabled'} = 1;

            #If theres a filter sub run it now.
            if ( defined $filterInclude ) {
                $log->debug("Checking to see if $device should be monitored");

                eval {
                    unless ( $filterInclude->( undef, $metricDef, $session ) )
                    {
                        $deviceHash{'enabled'} = 0;
                    }
                    1;
                };
                if ($@) {

                    #If there was any error at all, force the device
                    #enabled
                    $deviceHash{'enabled'} = 1;
                }

                if ( $deviceHash{'enabled'} ) {
                    $log->debug("Determined that $device SHOULD be monitored");
                }
                else {
                    $log->debug(
                        "Determined that $device SHOULD NOT be monitored");
                }
            }

            #test the valbase
            my $val = $session->getValue( $valbase, 1 );
            defined $val or next METRIC;  #Could be zero

            $log->debug("Found $metric on $target $device");

            #See if there should be a max value for this metric
            if ( $metricDef->{'maxbase'} ) {
                $max = $session->getValue( $metricDef->{'maxbase'}, 1 );
                defined $max or next METRIC;  #Could be zero

                $log->debug("Got the max $max for $metric");
            }

            #essentials for a non-mapped metric (tested earlier)
            $deviceHash{'target'}  = $target;
            $deviceHash{'metric'}  = $metric;
            $deviceHash{'valbase'} = $valbase;
            $deviceHash{'device'}  = $device;

            #optionals
            $metricDef->{'category'}
              and $deviceHash{'category'} = $metricDef->{'category'};
            $metricDef->{'conversion'}
              and $deviceHash{'conversion'} = $metricDef->{'conversion'};
            $metricDef->{'counterbits'}
              and $deviceHash{'counterbits'} = $metricDef->{'counterbits'};
            $metricDef->{'maxbase'}
              and $deviceHash{'max'} = $max;
            $metricDef->{'graphdef'}
              and $deviceHash{'graphdef'} = $metricDef->{'graphdef'};
            $metricDef->{'valtype'}
              and $deviceHash{'valtype'} = $metricDef->{'valtype'};
            $metricDef->{'graphgroup'}
              and $deviceHash{'graphgroup'} = $metricDef->{'graphgroup'};
            $metricDef->{'aggregate'}
              and $deviceHash{'aggregate'} = $metricDef->{'aggregate'};
            $deviceHash{'graphorder'} = $metricDef->{'graphorder'} || 10;

            push @return, \%deviceHash;
        }

        #If we get this far then the metric is valid for this device.
        #check if its supposed to be authoritive
        if ( $metricDef->{'authoritive'} ) {
            $authoritives{$metric} = 1;
        }
        $log->info("$metric found on $target");
    }

    return wantarray ? @return : \@return;

}

1;
