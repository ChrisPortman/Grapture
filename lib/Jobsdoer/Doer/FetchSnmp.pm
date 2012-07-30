#!/usr/bin/env perl
# $Id: FetchSnmp.pm,v 1.5 2012/06/07 03:41:22 cportman Exp $

=head1 NAME

  Jobsdoer::Doer::FetchSnmp.pm
 
=head1 SYNOPSIS

  use Jobsdoer::Doer::FetchSnmp;
  $job = Jobsdoer::FetchSnmp->new( { target    => '<target>',
                                     version   => '<version>', 
                                     community => '<community>',
                                     metrics   => [
                                         { name    => '<metricname>',
										   device  => '<device>',
                                           mapbase => '<mapbase>',
                                           base    => '<oidbase>',
                                           counterbits => '<No.ofBits>'
                                           munge   => '<mungename>',
                                         },
                                         ...
                                     ],
                                   },
                             
  );
  
  if ( not $job->error() ) {
      $result = $job->run();
  }

=head1 DESCRIPTION
  
  Processes the data passed in the data structure provided when calling 
  new() then runs a Net::SNMP->get_table() against the <target> for the
  supplied OIDs.
  
  The new() constructor method accepts a single hash reference.  The hash
  will contain various details regarding how to communicate with the 
  device.  In addition it will have a metrics key which will contain
  a list of hash refs.  Each hashref will describe a specific metric to 
  be polled on a specific device within the target system.  In this
  context, 'target' refers to a complete system such as a router or 
  server that will respond to SNMP get requests whereas 'device' referes
  to a component in that system for which details can be polled such as
  a network interface or hard disk.  Metric refers to a specific detail
  relating to a device such as Octects In for a network interface or
  free space in relation to a hard disk.  If a metric does not refer to
  a 'device' then it will be assumed to refer to the overall system (and
  will be assigned to a pseudo device called 'system') such would be the
  case with metrics like 'Load' (not to be confused with CPU usage which
  would more correctly be associated with a 'CPU' device), 'Memory Usage'
  , swap etc.
  
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
  
=head3 Munge (optional)

  The munge values is the name of a function that will process and
  manipulate the value in some way.  Eg, one munging function takes the
  interface Octet In and Out values which come off the system in the form
  of a counter value, and translates them into an Octets per second value.
  
  The term 'Munge' was ripped off from the SNMP::Info modules.
  
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

package Jobsdoer::Doer::FetchSnmp;

use lib '../../';
use strict;
use warnings;
use Net::SNMP;
use Data::Dumper;
use Log::Dispatch;

my $logger = Log::Dispatch->new(
    outputs   => [
        [ 'Syslog', 'min_level' => 'info', 'ident'  => 'JobWorker' ],
        [ 'Screen', 'min_level' => 'info', 'stderr' => 1, 'newline' => 1 ],
    ],
    callbacks => [
        \&_logPrependLevel,
    ]
);

sub new {
    my $class = shift;
    $class = ref($class) if ref($class);    #in case we're cloning the obj.

    my $params = shift
      if ( ref( $_[0] ) and ref( $_[0] ) eq 'HASH' );

    my %maps;
    my %polls;
    my $target;
    my $version;
    my $community;

    if ($params) {
        $target    = $params->{'target'};
        $version   = $params->{'version'};
        $community = $params->{'community'};
        
        #build a deduped list of map table oids. and a hash of metrics
        for my $job ( @{$params->{'metrics'}} ) {
            #if there is no device, then the metric must be a system wide one
            # eg Load			
			my $device = $job->{'device'} ? $job->{'device'}
			                              : 'System';

			#stash the mapbase into the maps hash so that they are deduped
			if ( $job->{'mapbase'} ){
				$maps{ $job->{'mapbase'} } = 1;
			}
			
            #create a hash of things to poll
			unless ( $polls{$device} ) { $polls{$device} = []; };
			push $polls{$device}, $job;
		}
    }

    #build the opbject    
    my %jobParams = (
        '_target'    => $target,
        '_version'   => $version,
        '_community' => $community,
        '_maps'      => \%maps,
        '_polls'     => \%polls,
        '_error'     => undef,
    );

    my $self = bless \%jobParams, $class;

    return $self;
}

sub run {
    my $self = shift;
    $|++;


    #check we have everything we need.
    if ( not $self->validateParams() ) {
        $self->{_error} =
'Parameter validation failed.  Either not all the parameters we supplied, the version was invalid or an unchecked/uncleared error was present';
        return;
    }

    #Make the object vars easier to access.
    my $target    = $self->{'_target'};
    my $version   = $self->{'_version'};
    my $community = $self->{'_community'};
    my %maps      = %{ $self->{'_maps'} };
    my %polls     = %{ $self->{'_polls'} };
    my %mapResultsHash;
    my @mapResults;
    
    $logger->debug( "Starting SNMP fetch for $target with community string $community" );

    #Create the SNMP session to the device.
    my ( $session, $error ) = Net::SNMP->session(
        -hostname    => $target,
        -version     => $version,
        -community   => $community,
    );

    if ($error) {
        $self->{'_error'} = $error;
        return;
    }
    
    if ($session) {
		$logger->debug( "Connected to $target" );
	}
	else {
		return;
	}
	
    #get all the map tables.
    for my $mapBase ( keys %maps ) {
        $logger->debug( "Getting map table $mapBase..." );
        my $result = $session->get_table( '-baseoid'         => $mapBase,
                                          '-maxrepetitions'  => 10, );

        unless ($result) {
			$logger->error( "Getting map table FAILED" );
            if ( $error = $session->error() ) {
				$logger->error($error);
                $self->{'_error'} = $error;
            }
            $session->close();
            return;
        }
        push @mapResults, $result;
    }
    
    #push each hash into a single hash
    for my $hash ( @mapResults ) {
		%mapResultsHash = ( %mapResultsHash, %{$hash} );
	}
    
    #reverse the mapResults so the oid becomes the value and then trim the oid so we only keep the index
    %mapResultsHash = reverse( %mapResultsHash );
    for my $key (keys %mapResultsHash) {
		$mapResultsHash{$key} =~ s/.+(\.\d+)$/$1/;  #value now looks like '.1'
    }

    #do the polling
    my @pollsResults;
    my %queuedValmaps;
    my %fullResultHash;
    my %timestamps;

    for my $device ( keys %polls ) {
		
		for my $metric ( @{ $polls{$device} } ) {
		    
		    my $oid;
		    $oid = $metric->{'valbase'};
		    $oid =~ s/\.$//; #remove any trailing period
		    
		    #add the mapped index if applicable.
		    if ($mapResultsHash{$device}) {
			    $oid .= $mapResultsHash{$device};
			}
			elsif ( $mapResultsHash{ $metric->{'metric'} } ) {
				$oid .= $mapResultsHash{ $metric->{'metric'} };
			}
			
			#stash some extra details into the $metric hash for convienience
			$metric->{'target'}    = $target;
			$metric->{'oid'}       = $oid;
			
			#if this is a mapped metric, then get the whole val table
			#otherwise just get the oid
			my $result;
			unless ( exists($fullResultHash{$oid}) ) {
				if ($metric->{'mapbase'}) {
			        $result = $session->get_table(
			            -baseoid  => $metric->{'valbase'},
			            -maxrepetitions  => 10,
			        );
			        $timestamps{$metric->{'valbase'}} = time();
				}
				else {
			        $result = $session->get_request(
			            -varbindlist  => [$metric->{'valbase'}],
			        );
			        $timestamps{$metric->{'valbase'}} = time();
				}
		
		        if ( not $result ) {
					debug( " FAILED\n" );
		            if ( $error = $session->error() ) {
		                $self->{'_error'} = $error;
		            }
		            $session->close();
		            return;
		        }
		        
		        for my $key ( keys(%{$result}) ) {
					$fullResultHash{$key} = $result->{$key};
				}
			}
			else {
			}

            #get the timestamp from when the snmp data was actually 
            #collected which could be many seconsds prior to doing the
            #processing.			
		    $metric->{'timestamp'} = $timestamps{$metric->{'valbase'}};
		    $metric->{'value'}     = $fullResultHash{$oid};
    
            push @pollsResults, $metric;   
	        
		}
    }

    $session->close();
    $logger->debug( "Finished snmp getting $target" );
    
    return \@pollsResults;
}

sub validateParams {
    my $self = shift;

    if (    $self->{_target}
        and $self->{_version}
        and $self->{_community}
        and $self->{_polls}
        and not $self->{_error} )
    {

        return 1 if $self->{_version} =~ m/^[123]$/;
        return;
    }
    else {
        return;
    }
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

sub _logPrependLevel {
	my %options = @_;
	
	my $message = $options{'message'};
	my $level   = uc($options{'level'});
	
	$message = "($level) $message"
	  if $level;
	
	return $message;
}

1;
