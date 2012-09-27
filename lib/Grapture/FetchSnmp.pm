#!/bin/false
# $Id: FetchSnmp.pm,v 1.5 2012/06/07 03:41:22 cportman Exp $

=head1 NAME

Grapture::FetchSnmp.pm
 
=head1 SYNOPSIS

  use Grapture::FetchSnmp;
  $obj = Grapture::FetchSnmp->new( { target    => '<target>',
                                     version   => '<version>', 
                                     community => '<community>',
                                   },
  );
  
  $obj->pollProcess( 
    {             
        'maps'  => { <OID> => 1, <OID> => 1 ... },
        'polls' => { <device> => 
            [
                { 
                    'metric'      => <metric_name>,
                    'device'      => <device_name>,
                    'valbase'     => <OID>,
                },
                ...
            ]  
        }
    }
  );


=head1 DESCRIPTION

Provides an OO interface to a target with methods to then retrive
details from the target.
  
=head1 METHODS



=head1 DATA STRUCTURE

The following describes in further detail each of the key/values that
make up the data structure and how they are used.

=head2 Target

Target is the IP address or hostname (that can be resolved to the
correct IP address) of the system to be polled/monitored.

=head2 Version

The version referes to the SNMP version that should be used when
retrieving data from the system.  This module currently supports
versions 1 and 2 (aka 2c) and thus the value for version should be '1'
or '2'.  At this time, version 3 is not supported but will be added
when the need arrises.

=head2 Community

The community value should be the SNMP community configured on the
target allowing read access.

=head2 Metrics

Metrics is a key that stores a list of hash refs describing the
individual pieces of data that should be retrived from the device and
how to handle it.  Each hash will have the following keys (optional
ones will be marked so):

=head3 Name

Name is the name of the metric such as 'Octects In'

=head3 Device (optional)

As discussed previously, device referes to a specific component in the
system such as a network interface or hard drive.  If this is not
provided, the metric is assumed to relate to the system as a whole and
provided 'system' as the device name.

=head3 Mapbase (optional)

Mapbase is used in the mapping process. The mapping process allows the
polling logic to poll devices specified by name (eg 'eth0'). The map
base should be an OID that referes to a table that contains the device
names. The retrieved table is then stored as a hash whos keys are the
available device names and the values are the last digit in the full
oid relating to the device name. This digit, when appended to the metric
table OID (base), yeilds a metric value specific to the desired device.

Using a mapping logic is important becuase:
a) It allows us to use the friendly device name rather than having to
 know the devices index in the SNMP tables.
b) There is no guarentee that a specific device will maintain the same
 index in the SNMP tables accross reboots.

Another noteworthy point is that if the system is a large switch for
example with many interfaces being polled, the metric hash for each
interface will have the same map base OID. Despite this, the map base
will only be retrieved once and reused for each interface.

=head3 Base

This is the base oid corresponding to the metric being retrieved. It
may be a full OID for a leaf object in the case of a system wide value
(such as 'load') or it may be a table OID, in which case a value from
the map table (see Mapbase) would be appended to derive the complete
OID.

=head3 CounterBits (optional)

When polling counters generally they can be 32bit or 64bit counters
(often systems will offer the same metric in both 32 and 64 bit using
different OIDs). Knowing which we are using is important because once
counters reach their maximum value ( 2 ** counterbits ) they restart
(aka 'roll') from zero.  Counter roll needs to be accounted for to
avoid wierd spikes in graphes and strange looking data. The counterbits
value is not used in this particular module but rather passed on to the
munging functions to help in their manipulations of the data.

=head2 OUTPUT

The result and return value is a reference to an array of hash
references each hash ref is the original hashref stored in metrics key
of the input with a couple of keys added:

=head3 Value

This is the value of the metric after the munging function, if
applicable, applied.

=head3 Timestamp

This is a timestamp in seconds since the POLLER WORKER systems epoc.
It is not the time from the target system.

=head3 Oid

This is the actual oid queried for the gigen metric on the given device.
It will be the base plus the map index if applicable.

=head3 Target

This is simply the target value from the input copied to the metric
output so that the information is available to further processing.

=head3 Output Structure

The structure of the output looks like the following, see the above
sections for descriptions on each key/value.

  [
      { name        => '<metricname>',
	    device      => '<device>',
	    mapbase     => '<mapbase>',
	    base        => '<oidbase>',
	    counterbits => '<No.ofBits>'
	    munge       => '<mungename>',
	    value       => '<postMungeResult>',
	    timestamp   => '<secsSinceEpoc>',
	    oid         => '<fullOid>',
	    target      => '<target'>,
	  },
	  ...,
  ]

=cut

package Grapture::FetchSnmp;

use strict;
use Net::SNMP;
use Data::Dumper;
use Log::Any qw ( $log );

=head2 new()

This method takes the details required to create an SNMP session to the
target.  With those details it will create the Net::SNMP object and
store it within the new object.

Arguments are supplied as a hash ref.

  my $target = Grapture::FetchSnmp->new(
      {
          'target'    => <target_address>,
          'version'   => {1|2},                  #snmp version
          'community' => <snmp_community_string>,
      }
  );

=cut 

sub new {
    my $class = shift;
    $class = ref($class) if ref($class);    #in case we're cloning the obj.

    my $params = shift
      if ( ref( $_[0] ) and ref( $_[0] ) eq 'HASH' );

    my $target;
    my $version;
    my $community;

    if ($params) {
        $target    = $params->{'target'};
        $version   = $params->{'version'};
        $community = $params->{'community'};
    }

    unless ( $target and $version and $community ) {
        $log->error( 'Required parameters for Grapture::FetchSnmp->new are missing');
        return;
    }

    #create an SNMP object for the target
    my ( $session, $error ) = Net::SNMP->session(
        -hostname  => $target,
        -version   => $version,
        -community => $community,
    );

    unless ($session) {
        if ($error) {
            $log->error( 'Could not create an SNMP session for '.$target.': '.$error );
            return;
        }
        $log->error( 'Could not create an SNMP session for '.$target);
        return;
    }

    $params->{'snmpSession'} = $session;

    my $self = bless $params, $class;

    return $self;
}

=head2 pollProcess()

This method takes a collection of polling tasks and processes each one 
and returns the task with the addition of the value and the timestamp at
which the actual value was retrieved.

Requires a single argument which must be a hash ref. The hash contains
2 keys, 'maps' and 'polls'.  Maps contains a reference to an array that
is a list of all the mapbase oids applicable to target and the polls for
it.  'polls' is a hash ref with a key for each device on the target, the
values for which describe each metric to poll for the device.

The method will first poll the target for each oid in the maps list to
build a library of device indexes this way we only have to do it once 
before we start polling the metrics.  Then process each device in the
'polls'.  If the device is found in the device map library, the valbase
is treated as a table and the whole table is retrieved and stored in a
cache. This way if another device with the same metric (thus value table
comes up, we can take the result straight from the cache.

  my $pollResults = $target->pollProcess(
      {
          maps  => [ <oid>, <oid>, ... ],
          polls => {
              <device> => {
                  metric  => <metric_name>,
                  valbase => <oid>,
              },
              ...
          }

=cut

sub pollProcess {
    my $self   = shift;
    my $params = shift;
    
    if (ref $params eq 'HASH') {
        unless (     ref($params->{'maps'}) eq 'ARRAY'
                 and ref($params->{'polls'}) eq 'ARRAY' ){
            return;
        }
    }
    else {
        $log->error( 'pollProcess expects a hash ref' );
        return;
    }

    $|++;

    #Make the object vars easier to access.
    my $target    = $self->{'target'};
    my $version   = $self->{'version'};
    my $community = $self->{'community'};
    my @maps      = @{ $params->{'maps'} };
    my @polls     = @{ $params->{'polls'} };
    my %mapResultsHash;
    my @mapResults;

    $log->debug(
        "Starting SNMP fetch for $target with community string $community");

    #get all the map tables.
    for my $mapBase ( @maps ) {
        $log->debug("Getting map table $mapBase for $target...");
        my $result = $self->getMapping($mapBase) || return;

        %mapResultsHash = ( %mapResultsHash, %{$result} );
    }

    #do the polling
    my @pollsResults;
    my %queuedValmaps;
    my %fullResultHash;
    my %timestamps;

    for my $poll ( @polls ) {
        my $device  = $poll->{'device'};
        my $metric  = $poll->{'metric'};
        my $valbase = $poll->{'valbase'};
        
        $log->debug("Polling $metric for $device on $target...");

        my $oid;
        $oid = $valbase;
        $oid =~ s/\.$//;    #remove any trailing period

        #add the mapped index if applicable.
        if ( $mapResultsHash{$device} ) {
            $oid .= '.'.$mapResultsHash{$device};
        }
        elsif ( $mapResultsHash{ $metric } ) {
            $oid .= '.'.$mapResultsHash{ $metric };
        }

        #if this is a mapped metric, then get the whole val table
        #otherwise just get the oid
        my $result;
        unless ( exists( $fullResultHash{$oid} ) ) {

            if (    $mapResultsHash{ $device } 
                 or $mapResultsHash{ $metric } ) {

                $result = $self->getTable( $valbase );
                $timestamps{ $valbase } = time();

                for my $key ( keys( %{$result} ) ) {
                    $fullResultHash{$key} = $result->{$key};
                }

            }
            else {

                $result = $self->getValue( $valbase );
                $timestamps{ $valbase } = time();
                $fullResultHash{$oid} = $result;

            }

            if ( not defined $result ) {
                $log->error('Did not get a result for '.$oid);
                return;
            }

        }

        #get the timestamp from when the snmp data was actually
        #collected which could be many seconsds prior to doing the
        #processing.
        $poll->{'timestamp'} = $timestamps{ $valbase };
        $poll->{'value'}     = $fullResultHash{ $oid };
        
        $log->debug("Got ".$poll->{'value'}." for $metric for $device on $target...");

        push @pollsResults, $poll;

    }

    $log->debug("Finished snmp getting $target");

    return \@pollsResults;
}

sub getTable {
    my $self     = shift;
    my $tableOid = shift || return;
    my $snmpObj = $self->{'snmpSession'};
    my $result;    
    my $error;
    
    unless ( $tableOid =~ /^.?(?:\d+\.)+\d*$/ ) {
        $log->error("$tableOid does not look like a valid OID");
        return
    }
    
    $snmpObj = $self->{'snmpSession'};
    $result = $snmpObj->get_table(
        -baseoid        => $tableOid,
        -maxrepetitions => 10,
    );
    
    unless ( $result ) {
        $log->error( "An error occured retriving $tableOid from "
                     .$self->{'_target'}.' : '
                     .$snmpObj->error()
        );
        return;
    }
    
    return wantarray ? %{$result} : $result;
}

sub getValue {
    my $self = shift;
    my $oid =shift || return;
    
    my $snmpObj = $self->{'snmpSession'};
    my $result;    
    my $error;

    unless ( $oid =~ /^.?(?:\d+\.)+\d*$/ ) {
        $log->error("$oid does not look like a valid OID");
        return
    }

    $result = $snmpObj->get_request( -varbindlist => [ $oid ] );
    
    unless ( $result ) {
        $log->error( "An error occured retriving $oid from "
                     .$self->{'_target'}.' : '
                     .$snmpObj->error()
        );
        return;
    }
        
    $result = $result->{$oid};
    
    return $result;
}

sub getMapping {
    #return a hash where the snmp values are the keys and the last
    #number of the oid is the value eg 'eth0' => 1
    my $self     = shift;
    my $tableOid = shift || return;

    my $table = $self->getTable( $tableOid);
    
    # Reverse the table so that the values become the keys.
    # It is possible that some of the entries are lost if there are 
    # duplicate values in the orriginal. 
    my %mapping = reverse( %{$table} );
    
    # Reduce the oids that are now the values down to just the index 
    # which is the last number in the OID.
    for my $key ( keys( %mapping ) ) {

        unless ( $mapping{$key} =~ s/\.(\d+)$/$1/ ) {
            $log->error('While building a mapping from '
                        .$tableOid.' on '.$self->{'target'}
                        .', the index for '.$key.' could not be determined. '
                        .$key.' will be ommited from the map'
            );
            delete $mapping{$key};
        }
    }
    
    return wantarray ? %mapping : \%mapping;
}


sub error {
    my ( $self, $keep ) = @_;

    if ( $self->{_error} ) {
        my $error = $self->{_error};
        $self->{_error} = undef if not $keep;
        return $error;
    }

    return;
}

1;
