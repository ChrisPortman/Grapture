#!/usr/bin/env perl
# $Id: Discovery.pm,v 1.2 2012/08/20 23:47:07 cportman Exp $

package Grapture::JobsProcessor::Doer::Discovery;

use strict;
use warnings;
use Net::SNMP;
use Log::Any qw ( $log );
use Data::Dumper;

#Use plugable modules to allow on the fly expansion of functionality
use Module::Pluggable
  search_path => ['Grapture::JobsProcessor::Doer::Discovery'],
  require     => 1,
  sub_name    => 'discoverers',
  inner       => 0;

sub new {
    my $class   = shift;
    my $options = shift;

    $class = ref($class) || $class;

    unless ( ref($options) and ref($options) eq 'HASH' ) {
        die "Arg must be a hash ref\n";
    }

    unless ($options->{'target'}
        and $options->{'version'}
        and $options->{'community'} )
    {
        die "Options must include 'target', 'version' and 'community'\n";
    }

    my ( $session, $error ) = Net::SNMP->session(
        '-hostname'  => $options->{'target'},
        '-version'   => $options->{'version'},
        '-community' => $options->{'community'},
    );

    unless ($session) {
        die "$error\n";
    }

    my %self = (
        'target'  => $options->{'target'},
        'session' => $session,
        'metrics' => [],
        'error'   => undef,
    );

    my $self = bless \%self, $class;

    return $self;
}

sub run {
    my $self = shift;

    my @discoveryMods = $self->discoverers();

    for my $discoverer (@discoveryMods) {
        my $params;
        eval { $params = $discoverer->discover($self); };
        if ($@) {
            warn
"An error occured trying to run $discoverer, its being ignored: $@\n";
            next;
        }

        if ( ref $params eq 'ARRAY' ) {

            my $result = $self->runDiscParams($params);

            if ( ref $result eq 'ARRAY' ) {
                push @{ $self->{'metrics'} }, @{$result};
            }
        }
    }

    return wantarray ? @{ $self->{'metrics'} } : $self->{'metrics'};
}

sub runDiscParams {
    my $self   = shift;
    my $params = shift;

    return unless ref $params eq 'ARRAY';

    my $target  = $self->{'target'};
    my $session = $self->{'session'};
    my $sysDesc;
    my $group;

    return unless ( $target and $session );

    my @return;
    my %devStateCache;  #Cache the results of filterInclude for each Dev
    my %authoritives;   #store a record of authoritive metric defs so that
                        #they are not over written.  
    
    #Get the sysdesc first.  It will be needed later.  Its also going to
    #a common requirenment of any device.  We also can use getting the 
    #sysdesc as an availabiltiy test for the device
	$sysDesc = $session->get_request(
		'-varbindlist' => ['.1.3.6.1.2.1.1.1.0'] );

	if ( $sysDesc->{'.1.3.6.1.2.1.1.1.0'} ) {
		$sysDesc = $sysDesc->{'.1.3.6.1.2.1.1.1.0'};
	}
	else {
		$self->error( "$target did not respond" );
		return;
	}

  METRIC:
    for my $metricDef ( @{$params} ) {
        next METRIC unless ref($metricDef) and ref($metricDef) eq 'HASH';

        my $metric  = $metricDef->{'metric'};
        unless ($metric =~ /^[a-zA-Z0-9_\-]{1,19}$/) {
			$log->error("Metric name $metric is invalid. Skipping");
			next METRIC;
		}
        
        my $valbase = $metricDef->{'valbase'};
        my $filterInclude;
        my $max;
        
        if ( $authoritives{$metric} ) {
			#We already have a metric def that is authoritive. Skip
			next METRIC;
		}

        if ( $metricDef->{'group'} ) {

            #this is a group definition hash
            #If we already have the group sorted. skip.

            next METRIC if $group;

          EXPRESSION:
            for my $exp ( @{ $metricDef->{'sysDesc'} } )
            {    # FIXME, i wonder if we can move this out to a config file?

                if ( $sysDesc =~ m/$exp/ ) {
                    $group = $metricDef->{'group'};
                    $log->info("Setting Group $group for $target");
                    last EXPRESSION;
                }

            }

            push @return,
              {
                'group'  => $group,
                'target' => $target,
              };

            next METRIC;
        }

        #look for a filter code ref
        if ( ref $metricDef->{'filterSub'} eq 'CODE' ) {
            $filterInclude = delete $metricDef->{'filterSub'};  
        }
        else {
            $filterInclude = '';
        }

        #essential params
        next METRIC
          unless ( $metricDef->{'metric'}
            and $metricDef->{'valbase'} );

        if ( $metricDef->{'mapbase'} ) {
            my $map;
            my $vals;

            #test the valbase

            $session->error();
            $vals = $session->get_table(
                '-baseoid'        => $metricDef->{'valbase'},
                '-maxrepetitions' => 10,
            ) or next METRIC;

            #we need to get the table for map base
            $map = $session->get_table(
                '-baseoid'        => $metricDef->{'mapbase'},
                '-maxrepetitions' => 10,
            ) or next METRIC;

            $map = { reverse( %{$map} ) };

            $log->debug("Got the map table for $metric");

            if ( $metricDef->{'maxbase'} ) {
                $max = $session->get_table(
                    '-baseoid'        => $metricDef->{'maxbase'},
                    '-maxrepetitions' => 10,
                ) or next METRIC;

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

                my ($devId) = $map->{$device} =~ m/(\d+)$/;
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
                if ( $filterInclude )
                {   
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
                $metricDef->{'munge'}
                  and $deviceHash{'munge'} = $metricDef->{'munge'};
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
                    unless (
                        $filterInclude->( undef, $metricDef, $session ) )
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
            my $val = $session->get_request(
                '-varbindlist' => [ $metricDef->{'valbase'} ] )
              or next METRIC;

            unless ( defined( $val->{ $metricDef->{'valbase'} } )
                and $val->{ $metricDef->{'valbase'} } ne 'noSuchObject' )
            {
                next METRIC;
            }

            $log->debug("Found $metric on $target $device");

            #See if there should be a max value for this metric
            if ( $metricDef->{'maxbase'} ) {
                print "Getting the max value for $target/$metric...\n";
                $max = $session->get_request(
                    '-varbindlist' => [ $metricDef->{'maxbase'} ] );
                ( $max and $max->{ $metricDef->{'maxbase'} } ) or next METRIC;

                $max = $max->{ $metricDef->{'maxbase'} };
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
            $metricDef->{'munge'}
              and $deviceHash{'munge'} = $metricDef->{'munge'};
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

sub error {
    my $self  = shift;
    my $error = shift;
    
    if ($error) {
		$self->{'error'} = $error;
	}
	
	$self->{'error'} and return $self->{'error'};
    
    return;
}

1;
