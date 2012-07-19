#!/usr/bin/env perl
# $Id:$

package Jobsdoer::Output::RRDTool;

use strict;
use warnings;

use Data::Dumper;
use RRDTool::OO;

my $RRDFILELOC = '/home/chris/git/Grasshopper/rrds/';

sub new {
    my $class  = ref $_[0] || $_[0];
    my $args   = $_[1];
    
    unless ( ref($args) and ref($args) eq 'ARRAY' ) {
		print "Arg not an array\n";
		return;
	}
    
    my %selfHash;
    $selfHash{'resultset'}  = $args;
    $selfHash{'rrdfileloc'} = $RRDFILELOC;
    
    my $self = bless(\%selfHash, $class);
    
    return $self;
}

sub run {
	my $self    = shift;
    my $results = $self->{'resultset'};
    
    my $target;     #A job is per target.
    my %rrdUpdates; #hash keyed on device.


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
			$target  = $result->{'target'};
		}
		
        unless ( $rrdUpdates{$device} ) {
	        $rrdUpdates{$device} = {};
		}
		
		$rrdUpdates{$device}->{$metric} = { 'time'     => $timestamp,
		                                    'value'    => $value,
		                                    'valtype'  => $valtype,
		                                    'max'      => $max,
		                                  };
		$rrdUpdates{$device}->{'category'} = $category,
		#print Dumper(\%rrdUpdates);
	}
	
	#process each device and its metrics and do some manipulations
	for my $updDevice (keys(%rrdUpdates)) {
		my $rrdFile;
		my $category = delete $rrdUpdates{$updDevice}->{'category'};

        #Add the hostname as a dir to the RRD file location.
        if ($target) {
        	$rrdFile = $self->{'rrdfileloc'}.$target.'/';
    		unless ( -d $rrdFile ) {
				print "Creating dir $rrdFile for $updDevice\n";
				mkdir $rrdFile
				  or return;
			}
		}
		else {
			return;
		}
		
		# Add the category to RRD file location if applicable
		if ($category) {
			$rrdFile .= $category.'/';
			unless ( -d $rrdFile ) {
				print "Creating dir $rrdFile for $updDevice\n";
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
			$devFileName =~ s|\/|_|g;

			$rrdFile .= $devFileName.'/';
			unless ( -d $rrdFile ) {
				print "Creating dir $rrdFile for $updDevice\n";
				mkdir $rrdFile
				  or return;
			}
		}
		else {
			return;
		}

		for my $updMetric (keys( %{$rrdUpdates{$updDevice} } )) {

			#finish the rrd file name and location with <metric>.rrd
			my $devFileName = $updMetric.'.rrd';
			$devFileName =~ s|\/|_|g;
			
	        my $finalFileName = $rrdFile . $devFileName;
	
	        # create a hash structure that can be feed straight to rrd update
			my %update = ( 'values'  => {}, 
			               'time'    => undef, 
			               'valtype' => {},
			               'valmax'  => {},
			             );


			my %updMetricHash = %{$rrdUpdates{$updDevice}->{$updMetric}};

	        $update{'values'}->{$updMetric}  = $updMetricHash{'value'};
	        $update{'valtype'}->{$updMetric} = uc($updMetricHash{'valtype'});
	        $update{'valmax'}->{$updMetric}  = $updMetricHash{'max'};
	        $update{'time'}                  = $updMetricHash{'time'};

		    $self->_pushUpdate($finalFileName, \%update)
		      or return;
		}
	}
	
	return 1;
}

sub _pushUpdate {
    my $self       = shift;
    my $rrdFile    = shift;
    my $updateHash = shift;
    my $rrdObj;
    
    #check that $updateHash is a hash ref.
    unless ( ref($updateHash) and ref($updateHash) eq 'HASH') {
		print "Arg not a hash\n";
	    return;
	}

    if ($rrdFile) {
		
		$rrdObj = RRDTool::OO->new( 'file'        => $rrdFile,
		                            'raise_error' => 0 )
		  or print "Failed to create RRD perl obj: ".$rrdObj->error_message()."\n" 
		    and return;

		$self->{'rrdObj'} = $rrdObj;
	
		unless ( -f $rrdFile ) {
			print "Creating file $rrdFile for\n";
			$self->_createRrd($updateHash)
			  or return;
		}
	}
	
	#Valtype and Max only needed for creation.
	my %update = ( 'time'   => $updateHash->{'time'}, 
	               'values' => $updateHash->{'values'},
	             );
	
	$rrdObj->update( %update )
		  or print "Update failed for $rrdFile: ".$rrdObj->error_message()."\n".Dumper($rrdObj)."\n".Dumper(\%update)."\n" and return;
		  
    return 1;
}

sub _createRrd {
    my $self       = shift;
    my $updateHash = shift;
    my $rrdObj     = $self->{'rrdObj'};
    my @datasources;
    
    for my $ds ( keys( %{$updateHash->{'values'}} ) ) {
		my $type = $updateHash->{'valtype'}->{$ds};
		my $max  = $updateHash->{'valmax'}->{$ds};
		
		my %dataSettings;
		$dataSettings{'name'}         = $ds;
		$dataSettings{'type'}         = uc($type);
		$max and $dataSettings{'max'} = $max;
		
		push @datasources, ( 'data_source', \%dataSettings );
	}
	
	#print Dumper(\%datasources);

	$rrdObj->create(
	    'step' => 60,
	    
	    @datasources,
	    
		'archive' => { 'rows'    => 2880, #10 days, AVG over 5Mins
		               'cpoints' => 1,
		               'cfunc'   => 'AVERAGE',
		             },
		'archive' => { 'rows'    => 4320, #90 days, AVG over 30Mins
		               'cpoints' => 6,
		               'cfunc'   => 'AVERAGE',
		             },
		'archive' => { 'rows'    => 8760, #2year days, AVG over 120Mins
		               'cpoints' => 24,
		               'cfunc'   => 'AVERAGE',
		             },
	)
	  or print "Failed to create RRD: ".$rrdObj->error_message()."\n" 
	    and return;
	
	return 1;
}
	
sub error{
    #dummy
    return;
}


1;
