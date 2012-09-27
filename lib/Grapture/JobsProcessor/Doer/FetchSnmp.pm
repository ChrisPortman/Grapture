#!/bin/false

=head1 NAME

Grapture::JobsProcessor::Doer::FetchSnmp.pm
 
=head1 SYNOPSIS

Gets a job via beanstalk and polls a device for each of the required 
metrics

=head1 DESCRIPTION

Does some validation of the parameters received in the job and then
feeds it through Grapture::FetchSnmp where all the Grapture SNMP
operations are defined.
  
=head1 DATA STRUCTURE

The following describes in further detail each of the key/values that
make up the data structure that is received as a Grapture job and how
they are used.

Example:
  
  $job = {
    'target'    => <target>,
    'version'   => <snmpversion>,
    'community' => <snmp community>,
    'metrics'   => [
        {
            'metric'      => <metric>,
            'device'      => <device>,
            'valbase'     => <valbase>,
            'mapbase'     => <mapbase>,
            'counterbits' => <counterbits>,
            'category'    => <category>,
            'max'         => <max>,
            'valtype'     => <valtype>,
        },
        ...
    ],
  }


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

=head3 Metric

Name is the name of the metric such as 'Octects In'

=head3 Device (optional)

As discussed previously, device referes to a specific component in the
system such as a network interface or hard drive.  If this is not
provided, the metric is assumed to relate to the system as a whole and
provided 'system' as the device name.

=head3 Valbase

This is the base oid corresponding to the metric being retrieved. It
may be a full OID for a leaf object in the case of a system wide value
(such as 'load') or it may be a table OID, in which case a value from
the map table (see Mapbase) would be appended to derive the complete
OID.

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
      { 
   	      target      => '<target'>,
          name        => '<metricname>',
	      device      => '<device>',
	      mapbase     => '<mapbase>',
	      valbase     => '<oidbase>',
	      counterbits => '<No.ofBits>'
	      value       => '<SNMP_Result>',
	      timestamp   => '<secsSinceEpoc>',
	      oid         => '<fullOid>',
	  },
	  ...,
  ]

=cut 

package Grapture::JobsProcessor::Doer::FetchSnmp;

    use strict;
    use warnings;
    use Data::Dumper;
    use Grapture::FetchSnmp;
    use Log::Any qw ( $log );

    # Use BEGIN to clear the module from %ISA so that it can be reloaded
    # and include any changes.
    BEGIN {
        my @catchChangesIn = ( 'Grapture::FetchSnmp' );
        
        for my $prerec ( @catchChangesIn ){
            $prerec .= '.pm';
            $prerec =~ s|::|/|g;
            
            if ( $INC{ $prerec } ) {
                delete $INC{ $prerec };
            }
        }
    }

    sub new {
        #dummy new until new() is deprecated.
        my $class = shift;
        my %dummy;
        return bless(\%dummy, $class);
    }
    
    sub run {
        my $self = shift;
        my $params = shift;
        
        unless ( $params and ref( $params ) eq 'HASH' ) {
            $log->error('FetchSnmp->run() expects a hash ref');
            return;
        }

        my %polls;
        my $target;
        my $version;
        my $community;
    
        $target    = $params->{'target'};
        $version   = $params->{'version'};
        $community = $params->{'community'};

        # Create a grapture SNMP object.        
        my $GraptureSnmp = Grapture::FetchSnmp->new( 
            { 
                'target'    => $target,
                'version'   => $version,
                'community' => $community,
            }
        ) || ( $log->error('Failed to create Grapture::Snmp object') and return);
            
        #Build a hash for the Grapture::FetchSnmp->pollProcess() process.
        my %jobParams = ( $params->{'metrics'} );
        
        #build the result data structure
        my %result;
        $result{'target'}  = $target;
        $result{'results'} = $GraptureSnmp->pollProcess(\%jobParams) 
          || ( $log->error('Grapture::Snmp did not return a result') and return);
        
        return wantarray ? %result : \%result;
    }

    sub error {
        #dummy shile OO is depricated.
        return;
    }

1;
