#!/usr/bin/env perl
# $Id: Discovery.pm,v 1.7 2012/06/18 02:57:41 cportman Exp $

package Jobsdoer::Doer::Discovery;

use strict;
use warnings;
use Net::SNMP;
use Data::Dumper;

#Use plugable modules to allow on the fly expansion of functionality
use Module::Pluggable search_path => ['Jobsdoer::Doer::Discovery'], 
                      require     => 1, 
                      sub_name    => 'discoverers',
                      inner       => 0; 
                      
sub new {
	my $class   = shift;
	my $options = shift;
	
	$class = ref($class) || $class;
	
	unless ( ref($options) and ref($options) eq 'HASH') {
		die "Arg must be a hash ref\n";
	}
	
	unless (     $options->{'target'} 
	         and $options->{'version'} 
	         and $options->{'community'} ) {
	    die "Options must include 'target', 'version' and 'community'\n";
	}
	
	my ($session, $error) = Net::SNMP->session( 
	    '-hostname'  => $options->{'target'},
	    '-version'   => $options->{'version'},
	    '-community' => $options->{'community'},
	);
	
	unless ($session) {
		die "$error\n";
	}
	
	my %self = ( 'target'  => $options->{'target'},
	             'session' => $session, 
	             'metrics' => [],
	           );
	
	my $self = bless \%self, $class;
	
	return $self;
}

sub run {
    my $self = shift;

	my @discoveryMods = $self->discoverers();
    
    for my $discoverer ( @discoveryMods ) {
		my $params;
		eval {
            $params = $discoverer->discover($self);				
		};
		if ( $@ ) { 
			warn "An error occured trying to run $discoverer, its being ignored: $@\n";
			next;
	    }
	    
	    if ($params and ref($params) and ref($params) eq 'ARRAY') {

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
	
	unless ($target and $session) {
		return;
	}
	
    my @return;
	
	METRIC:
	for my $metricDef ( @{$params} ) {
		next METRIC unless ref($metricDef) and ref($metricDef) eq 'HASH'; 
		
	
	    if ( $metricDef->{'group'} ) {
			#this is a group definition hash
			#If we already have the group sorted. skip.
			
			next METRIC if $group;
			
			#We only want to get the sysDesc once per target
			unless ( $sysDesc ) {
				#get the system description
				$sysDesc = $session->get_request( '-varbindlist' => [ '.1.3.6.1.2.1.1.1.0' ] );
	
				if ( $sysDesc->{'.1.3.6.1.2.1.1.1.0'} ) {
					$sysDesc = $sysDesc->{'.1.3.6.1.2.1.1.1.0'};
				}
				else {
					next METRIC;
				}
	
			}
			
			
			EXPRESSION:
			for my $exp ( @{$metricDef->{'sysDesc'}} ) {

				if ( $sysDesc =~ /$exp/) {
					print "\t- Match!\n";
					$group = $metricDef->{'group'};
					print "Setting Group = $group\n";
					last EXPRESSION;
				}
	
			}
			
			push @return, { 'group'  => $group,
			                'target' => $target,
			              };
			
			next METRIC;
		}
		
		
	
		#essential params
		unless ( $metricDef->{'metric'} and $metricDef->{'valbase'}) {
			next METRIC;
		}

		my $metric  = $metricDef->{'metric'};
		my $valbase = $metricDef->{'valbase'};
	   	my $max;
		
		if ($metricDef->{'mapbase'}) {
			#test the valbase
			
			$session->error();
			print "Testing $target/$metric...\n";
			$session->get_table( '-baseoid'        => $metricDef->{'valbase'},
			                     '-maxrepetitions' => 10, 
			                   )
			  or next METRIC;
			print "\tPASSED\n";
			  
			#we need to get the table for map base
	     	my $map;
	
			$map = $session->get_table( '-baseoid'        => $metricDef->{'mapbase'},
			                            '-maxrepetitions' => 10,
			                          );
			$map or next METRIC;
			
			$map = { reverse(%{$map}) };
			
			if ( $metricDef->{'maxbase'} ) {
				$max = $session->get_table( '-baseoid'        => $metricDef->{'maxbase'},
				                            '-maxrepetitions' => 10,
				                          );
				$max or next METRIC;
				
				#knock the max keys down to just the index part of the OID (last digit)
				for my $key ( keys(%{$max}) ) {
					my ($index) = $key =~ m/(\d+)$/;
					$index or next METRIC;
					
					$max->{$index} = delete $max->{$key};
				}
			}
			
			DEVICE:
			for my $device ( keys(%{$map}) ) {
				
				my $inclregex = $metricDef->{'inclregex'};
				my $exclregex = $metricDef->{'exclregex'};
				
				#inclregex and exclregex can be a single regex or an
				#array of regexes.
				if ($inclregex) {
					if (ref($inclregex) and ref($inclregex) eq 'ARRAY'){
						for my $regex (@{$inclregex}) {
			   				next DEVICE if $device =~ m/$regex/;
						}
					}
					else {
						next DEVICE if $device !~ m/$inclregex/;
					}
				}
				
				if ($exclregex) {
					if (ref($exclregex) and ref($exclregex) eq 'ARRAY'){
						for my $regex (@{$exclregex}) {
			   				next DEVICE if $device =~ m/$regex/;
						}
					}
					else {
		   				next DEVICE if $device =~ m/$exclregex/;
					}
				}
				
				my ($deviceIndex) = $map->{$device} =~ m/(\d+)$/;
				$deviceIndex or next DEVICE;
				
				my %deviceHash;
				
				#essentials for a mapped metric (tested earlier)
				$deviceHash{'target'}  = $target;
				$deviceHash{'metric'}  = $metric;
				$deviceHash{'device'}  = $device;
				$deviceHash{'valbase'} = $valbase;
				$deviceHash{'mapbase'} = $metricDef->{'mapbase'};
				
				#optionals
				$metricDef->{'category'} 
				    and $deviceHash{'category'}    = $metricDef->{'category'};
				$metricDef->{'munge'} 
				    and $deviceHash{'munge'}       = $metricDef->{'munge'};
				$metricDef->{'counterbits'} 
				    and $deviceHash{'counterbits'} = $metricDef->{'counterbits'};
				$metricDef->{'maxbase'} 
				    and $deviceHash{'max'}         = $max->{$deviceIndex};
				$metricDef->{'graphdef'}
				    and $deviceHash{'graphdef'}    = $metricDef->{'graphdef'};
     			$metricDef->{'valtype'}
	  				and $deviceHash{'valtype'}     = $metricDef->{'valtype'};
     			$metricDef->{'graphgroup'}
	  				and $deviceHash{'graphgroup'}  = $metricDef->{'graphgroup'};
	  				
	  			
				push @return, \%deviceHash;
			}
		}
		else {
			#this is not a mapped device.

            #test the valbase
            print "Testing $target/$metric...\n";
           	my $val = $session->get_request( '-varbindlist' => [$metricDef->{'valbase'}] )
			   or next METRIC;

            unless (    defined($val) 
                and defined( $val->{ $metricDef->{'valbase'} } ) 
                and $val->{ $metricDef->{'valbase'} } ne 'noSuchObject'){
		        next METRIC;
		    }
		    print "\tPASSED\n";
			
			#See if there should be a max value for this metric
			if ( $metricDef->{'maxbase'} ) {
				print "Getting the max value for $target/$metric...\n";
				$max = $session->get_request( '-varbindlist' => [$metricDef->{'maxbase'}] );
				($max and $max->{$metricDef->{'maxbase'}}) or next METRIC;
								
				$max = $max->{$metricDef->{'maxbase'}};
				print "\tGot $max for the maximum val for $metricDef->{'metric'}\n";
			}

			my %deviceHash;
			
			#essentials for a non-mapped metric (tested earlier)
			$deviceHash{'target'}  = $target;
			$deviceHash{'metric'}  = $metric;
			$deviceHash{'valbase'} = $valbase;
			$deviceHash{'device'}  = $metricDef->{'device'} ? $metricDef->{'device'}
			                                                : 'System';
	
			#optionals
			$metricDef->{'category'} 
			    and $deviceHash{'category'}    = $metricDef->{'category'};
			$metricDef->{'munge'} 
			    and $deviceHash{'munge'}       = $metricDef->{'munge'};
			$metricDef->{'counterbits'} 
			    and $deviceHash{'counterbits'} = $metricDef->{'counterbits'};
			$metricDef->{'maxbase'} 
			    and $deviceHash{'max'}         = $max;
			$metricDef->{'graphdef'}
				and $deviceHash{'graphdef'}    = $metricDef->{'graphdef'};
			$metricDef->{'valtype'}
				and $deviceHash{'valtype'}     = $metricDef->{'valtype'};
			$metricDef->{'graphgroup'}
  				and $deviceHash{'graphgroup'}  = $metricDef->{'graphgroup'};

				
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
