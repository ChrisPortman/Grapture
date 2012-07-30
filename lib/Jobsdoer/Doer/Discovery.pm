#!/usr/bin/env perl
# $Id: Discovery.pm,v 1.7 2012/06/18 02:57:41 cportman Exp $

package Jobsdoer::Doer::Discovery;

use strict;
use warnings;
use Net::SNMP;
use Data::Dumper;

#Use plugable modules to allow on the fly expansion of functionality
use Module::Pluggable
  search_path => ['Jobsdoer::Doer::Discovery'],
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

        if ( $params and ref($params) and ref($params) eq 'ARRAY' ) {

            my $result = $self->runDiscParams($params);

            if ( ref($result) and ref($result) eq 'ARRAY' ) {
                push @{ $self->{'metrics'} }, @{$result};
            }
        }
    }

    return wantarray ? @{ $self->{'metrics'} } : $self->{'metrics'};
}

sub runDiscParams {
    my $self   = shift;
    my $params = shift;

    ref($params) or return;
    ref($params) eq 'ARRAY' or return;

    my $target  = $self->{'target'};
    my $session = $self->{'session'};
    my $sysDesc;
    my $group;

    unless ( $target and $session ) {
        return;
    }

    my @return;
    my %devStateCache;    #Cache the results of filterInclude for each Dev

  METRIC:
    for my $metricDef ( @{$params} ) {
        next METRIC unless ref($metricDef) and ref($metricDef) eq 'HASH';

        my $metric  = $metricDef->{'metric'};
        my $valbase = $metricDef->{'valbase'};
        my $max;

        print "\nExamining $metric for $target...\n" if $metric;

        if ( $metricDef->{'group'} ) {

            #this is a group definition hash
            #If we already have the group sorted. skip.

            next METRIC if $group;

            #We only want to get the sysDesc once per target
            unless ($sysDesc) {

                #get the system description
                $sysDesc = $session->get_request(
                    '-varbindlist' => ['.1.3.6.1.2.1.1.1.0'] );

                if ( $sysDesc->{'.1.3.6.1.2.1.1.1.0'} ) {
                    $sysDesc = $sysDesc->{'.1.3.6.1.2.1.1.1.0'};
                }
                else {
                    next METRIC;
                }

            }

          EXPRESSION:
            for my $exp ( @{ $metricDef->{'sysDesc'} } ) {

                if ( $sysDesc =~ m/$exp/ ) {
                    $group = $metricDef->{'group'};
                    print "Setting Group = $group\n";
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
        if (    ref( $metricDef->{'filterSub'} )
            and ref( $metricDef->{'filterSub'} ) eq 'CODE' )
        {
            print "Setting filterSub for $metric\n";
            *filterInclude = delete $metricDef->{'filterSub'};
            if ( defined &filterInclude ) {
                print "Filtersub successfully defined\n";
            }
            else {
                print "Filtersub FAILED to define!\n";
            }
        }
        else {
            print "No filterSub for $metric\n";
            undef *filterInclude;
        }

        #essential params
        unless ( $metricDef->{'metric'} and $metricDef->{'valbase'} ) {
            next METRIC;
        }

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

            if ( $metricDef->{'maxbase'} ) {
                $max = $session->get_table(
                    '-baseoid'        => $metricDef->{'maxbase'},
                    '-maxrepetitions' => 10,
                ) or next METRIC;

         #knock the max keys down to just the index part of the OID (last digit)
                for my $key ( keys( %{$max} ) ) {
                    my ($index) = $key =~ m/(\d+)$/;
                    $index or next METRIC;

                    $max->{$index} = delete $max->{$key};
                }
            }

          DEVICE:
            for my $device ( keys( %{$map} ) ) {

                #make sure that the device appears in the $vals for this
                #metric.  Not all devices in the map will have all the
                #metrics we've specified

                my ($devId) = $map->{$device} =~ m/(\d+)$/;
                my $devValOid = $valbase . '.' . $devId;
                $devValOid =~ s/\.\././;

                print
"Looking for $devValOid in vals table for device $device metric $metric... ";

                unless ( defined $vals->{$devValOid} ) {
                    print "NOT FOUND, SKIPPING\n";
                    next DEVICE;
                }
                print "FOUND\n";

                my %deviceHash;

                $deviceHash{'enabled'} = 1;

                #If theres a filter sub run it now.
                if ( defined &filterInclude ) {

                    if ( defined $devStateCache{$device} ) {
                        $deviceHash{'enabled'} = $devStateCache{$device};
                    }
                    else {
                        eval {
                            unless (
                                filterInclude( $devId, $device, $metricDef, $session ) )
                            {
                                $deviceHash{'enabled'} = 0;
                            }
                        };

                        if ($@) {
                            #If there was any error at all, force the device
                            #enabled
                            $deviceHash{'enabled'} = 1;
                        }
                        $devStateCache{$device} = $deviceHash{'enabled'};
                    }
                }

                my ($deviceIndex) = $map->{$device} =~ m/(\d+)$/;
                $deviceIndex or next DEVICE;

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
                  and $deviceHash{'max'} = $max->{$deviceIndex};
                $metricDef->{'graphdef'}
                  and $deviceHash{'graphdef'} = $metricDef->{'graphdef'};
                $metricDef->{'valtype'}
                  and $deviceHash{'valtype'} = $metricDef->{'valtype'};
                $metricDef->{'graphgroup'}
                  and $deviceHash{'graphgroup'} = $metricDef->{'graphgroup'};

                push @return, \%deviceHash;
            }
        }
        else {
            #this is not a mapped device.

            my %deviceHash;
            $deviceHash{'enabled'} = 1;

            #If theres a filter sub run it now.
            if ( defined &filterInclude ) {
                eval {
                    unless ( filterInclude( undef, $metricDef, $session ) )
                    {
                        $deviceHash{'enabled'} = 0;
                    }
                };
                if ($@) {
                    #If there was any error at all, force the device
                    #enabled
                    $deviceHash{'enabled'} = 1;
                }
            }

            #test the valbase
            print "Testing $target/$metric...\n";
            my $val = $session->get_request(
                '-varbindlist' => [ $metricDef->{'valbase'} ] )
              or next METRIC;

            unless (defined($val)
                and defined( $val->{ $metricDef->{'valbase'} } )
                and $val->{ $metricDef->{'valbase'} } ne 'noSuchObject' )
            {
                next METRIC;
            }
            print "\tPASSED\n";

            #See if there should be a max value for this metric
            if ( $metricDef->{'maxbase'} ) {
                print "Getting the max value for $target/$metric...\n";
                $max = $session->get_request(
                    '-varbindlist' => [ $metricDef->{'maxbase'} ] );
                ( $max and $max->{ $metricDef->{'maxbase'} } ) or next METRIC;

                $max = $max->{ $metricDef->{'maxbase'} };
                print
                  "\tGot $max for the maximum val for $metricDef->{'metric'}\n";
            }

            #essentials for a non-mapped metric (tested earlier)
            $deviceHash{'target'}  = $target;
            $deviceHash{'metric'}  = $metric;
            $deviceHash{'valbase'} = $valbase;
            $deviceHash{'device'} =
                $metricDef->{'device'}
              ? $metricDef->{'device'}
              : 'System';

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

            push @return, \%deviceHash;
        }

    }

    return wantarray ? @return : \@return;

}

sub error {

    #dummy for the momoent
    return 1;
}

1;
