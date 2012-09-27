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
      [
          { 
              'metric'  => <metric_name>,
              'device'  => <device_name>,
              'valbase' => <OID>,
              'mapbase' => <oid>, #Include for devices that have an
                                  #index eg Network interfaces. This
                                  #is the oid that has the index table.
          },
          ...
      ]  
  );


=head1 DESCRIPTION

Provides an OO interface to a target with methods to then retrive
details from the target.
  
=head1 METHODS

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
    $params->{'snmpCounter'} = 0;

    my $self = bless $params, $class;

    return $self;
}

=head2 pollProcess()

This method takes a collection of polling tasks and processes each one 
and returns the task with the addition of the value and the timestamp at
which the actual value was retrieved.

Requires either a single argument which is an ARRAY ref that contains
one or more HASH refs or an arbitrary number of HASH ref arguments. 

For each hash in the array or list, if there is a mabbase, it will see if
we already have the device ID cached, if not the index table will be
retrived using the mapbase oid and all the devices and their indexes
will be cached ensuring that if there are 100 interfaces, we only get
the index table once.

The, again if its there is a mapbase, the valbase will also be a table.
We get the whole table and cache the entire table of values.  Again, if
there are 100 interfaces, we only get the values for each metric once.

If there is no mapbase, then a simple get for the specific oid in valbase
is done.

  my $pollResults = $target->pollProcess(
     [
          {
              device  => <device_name>,
              metric  => <metric_name>,
              valbase => <oid>,
              mapbase => <oid>,  #Include for devices that have an
                                 #index eg Network interfaces. This
                                 #is the oid that has the index table.
          },
          ...
      ]
  );

The return is the same array of poll hashes as provided in the poll key
with 'value' and 'timestamp' keys added.  In reallity there will be many
other keys in the polls hashes however they are not relevant here but 
probably relevant to the Grapture output module.  This is why we simply
augment the supplied data structure with new values.

The return is either a hash or reference to a hash depending on the 
calling context.


=cut

sub pollProcess {
    my $self   = shift;
    my $params = ref $_[0] eq 'ARRAY' ? shift : \@_ ;
    
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
    my @polls     = @{ $params->{'polls'} };

    $log->debug(
        "Starting SNMP fetch for $target with community string $community");
    
    #do the polling
    my @pollsResults;
    my %queuedValmaps;
    my %fullResultCache;
    my %mapResultsCache;
    my %timestamps;

    for my $poll ( @polls ) {
        my $device  = $poll->{'device'};
        my $metric  = $poll->{'metric'};
        my $valbase = $poll->{'valbase'};
        my $mapbase = $poll->{'mapbase'} || undef;
        
        $log->debug("Polling $metric for $device on $target...");

        my $oid;
        $oid = $valbase;
        $oid =~ s/\.$//;    #remove any trailing period

        if ($mapbase) {
            if ( defined $mapResultsCache{ $device } 
                 or defined $mapResultsCache{ $metric } ) {
                
                $oid .= '.'.$mapResultsCache{$device} 
                  || $mapResultsCache{ $metric };
            }
            else {
                #We havent grabed this map table yet. Get it and cache it
                my $mapTable = $self->getMapping($mapbase) || return;
                %mapResultsCache = ( %mapResultsCache, %{ $mapTable } );
                $oid .= '.'.$mapResultsCache{ $device } 
                  || $mapResultsCache{ $metric };
           }
        }
                

        #if this is a mapped metric, then get the whole val table
        #otherwise just get the oid
        my $result;
        
        unless ( exists( $fullResultCache{$oid} ) ) {
            $log->debug("$oid not in cache. Must fetch");
            
            if (    $mapResultsCache{ $device } 
                 or $mapResultsCache{ $metric } ) {

                $result = $self->getTable( $valbase );
                $timestamps{ $valbase } = time();

                for my $key ( keys( %{$result} ) ) {
                    $fullResultCache{$key} = $result->{$key};
                }

            }
            else {

                $result = $self->getValue( $valbase );
                $timestamps{ $valbase } = time();
                $fullResultCache{$oid} = $result;

            }

            if ( not defined $result ) {
                $log->error('Did not get a result for '.$oid);
                return;
            }

        }
        else {
            $log->debug("Found $oid in cache");
        }

        #get the timestamp from when the snmp data was actually
        #collected which could be many seconsds prior to doing the
        #processing.
        $poll->{'timestamp'} = $timestamps{ $valbase };
        $poll->{'value'}     = $fullResultCache{ $oid };
        
        $log->debug("Got ".$poll->{'value'}." for $metric for $device on $target...");

        push @pollsResults, $poll;

    }

    $log->info("Finished snmp getting $target using ".$self->{'snmpCounter'}.' SNMP gets.');

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
    
    $self->{'snmpCounter'} ++;
    
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
    
    $self->{'snmpCounter'} ++;
    
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

        unless ( $mapping{$key} =~ s/.+(\d+)$/$1/ ) {
            $log->error('While building a mapping from '
                        .$tableOid.' on '.$self->{'target'}
                        .', the index for '.$key.' could not be determined. '
                        .$key.' will be ommited from the map'
            );
            delete $mapping{$key};
        }
    }

    $self->{'snmpCounter'} ++;
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
