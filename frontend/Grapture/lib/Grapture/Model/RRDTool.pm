package Grapture::Model::RRDTool;
use Moose;
use namespace::autoclean;

use RRDs;
use Time::Local qw(timelocal_nocheck timegm_nocheck);
use Data::Dumper;

extends 'Catalyst::Model';

=head1 NAME

Grapture::Model::RRDTool - Catalyst Model

=head1 DESCRIPTION

Catalyst Model.

=head1 AUTHOR

Chris Portman

=head1 LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

__PACKAGE__->meta->make_immutable;

my $RRDFILELOC            = $Grapture::GHCONFIG->{'DIR_RRD'};
my $STATIC_GRAPH_BASE_DIR = $Grapture::GHCONFIG->{'STATIC_GRAPH'};
my $RRDCACHED_ADDR        = $Grapture::GHCONFIG->{'RRD_BIND_ADDR'};
$RRDFILELOC               =~ s|([^/])$|$1/|;
$STATIC_GRAPH_BASE_DIR    =~ s|([^/])$|$1/|;

#Blue Red  Green Yellow Pink Peach DGreen Ivory Lavendar
my @COLOURS = qw( a8d0d8 eabcbf bddcb3 
                  f2de7d ddadbd efc5ac 
                  a4ce9e f3e3bf d7c3cf);


sub getRrdData {
	#suck in all the RRDS in $dir and extract all the metric data.
    my $self   = shift;
    my $c      = shift;

    my $target = $c->request->params->{'target'}   || return;
	my $fsdev  = $c->request->params->{'device'}   || return;
	my $cat    = $c->request->params->{'category'} || return;

    my %metricGroups;
    my %objsByGroups;
    my $dev = $fsdev;
    $dev =~ s|_SLSH_|/|g;
    
    my $dir = $RRDFILELOC . $target .'/'.$cat.'/'.$fsdev;
    unless ( -d $dir ) {
		print "no directory $dir\n";
		return;
	}
	
    my $devMetrics = $c->model('Postgres')->getDeviceMetrics($target, $dev);

	for my $met ( @{$devMetrics} ){
		my $metName = $met->{'metric'};
		my $group   = $met->{'graphgroup'} || $metName;
		my $order   = $met->{'graphorder'};
		
		next unless -f $dir.'/'.$metName.'.rrd';
		
		unless ( $metricGroups{$group} ) {
			$metricGroups{$group} = [];
		}
		
		push @{$metricGroups{$group}}, $metName;
	}
	
    my $graphGroupSettings = $c->model('Postgres')->getGraphGroupSettings(); 
    
	my $time = time();
	my $timeZoneOffset = $time - timelocal_nocheck(gmtime($time));

	GROUPS:
	for my $group ( keys %metricGroups ) {
		$objsByGroups{$group} = {};
    	my $dsCounter = 0;
		
		for my $metName ( @{$metricGroups{$group}} ) {
			my $file = $dir.'/'.$metName.'.rrd';
			
			#if using daemon use a relative path flush the files first
			$self->flushCacheToRrd($file);
			
			my $info = RRDs::info($file);
			my $step = $info->{'step'};
            
			#process each RRA (archive) in the object.
			my $rraNo = 0;
			NEWRRA:
			while ( $info->{'rra['.$rraNo.'].rows'} ) {
				my $rows   = $info->{'rra['.$rraNo.'].rows'};
				my $pdpPerRow = $info->{'rra['.$rraNo.'].pdp_per_row'};
				
				my $earliestData = $time - ($step * $pdpPerRow * $rows);
	            my $periodName = 'Since '.gmtime($earliestData);
	            
				my @plots;

                my ($start,$step,$names,$data)
                    = RRDs::fetch($file, 'AVERAGE', '--start', $earliestData);
			    my $error = RRDs::error;
			    print "$error\n" if $error;

                $start += $timeZoneOffset;
                
				#if theres a max val involved for a metric, I dont want
				#go to the DB if max isnt relevant (not in the settings)
				#but I also only want to go there once. so declare the 
				#var outside the loop.
				my $max;
					
                for my $metricData ( @{$data} ) {
					#$metricData is an Array of arrays. Each inner Array
					#is the vals for each metric on a specific time slot
					
					for my $value ( @{$metricData} ) {
						if ($value) {
							
							#some graph settings require some manipulation of data
							if ( $graphGroupSettings->{$group}->{'mirror'} 
							     and ($dsCounter % 2) ) {
							    #invert every 2nd metric to make negative vals to create the mirror
							    $value = -$value;
							}
							elsif (    $graphGroupSettings->{$group}->{'percent'} 
		                           and ( $max or $max = $c->model('Postgres')->getMetricMax($target,$dev,$metName) ) ) {
                                #calculate the percentage
							    $value = $value / $max * 100;
							}
						}
						push @plots, [ $start * 1000, $value ];
					}
					
					$start += $step;
				}

				push @{$objsByGroups{$group}->{$earliestData}},
				  { 'label' => $metName, 'plots' => \@plots };
				  
				$rraNo ++;
			}

			$dsCounter ++;
		}
		
		#Add graph settings to the group that come from the database
		for my $key ( keys %{$graphGroupSettings->{$group}} ){
			unless ( $objsByGroups{$group}->{'settings'} ) {
				$objsByGroups{$group}->{'settings'} = {};
			}

			$objsByGroups{$group}->{'settings'}->{$key} = 
			  $graphGroupSettings->{$group}->{$key};
		}
		
		#If there are no static graph settings from the DB, apply some
		#sencible ones
		unless ($objsByGroups{$group}->{'settings'}) {
			$objsByGroups{$group}->{'settings'} = {};
			
			if ( $dsCounter == 1 ) {
				#if there is only 1 metric, make it a filled area
				$objsByGroups{$group}->{'settings'}->{'fill'} = 1;
			}
		}
		
	}

    return wantarray ? %objsByGroups : \%objsByGroups;
}

sub getAggRrdData {
	my $self = shift;
	my $c = shift;
	my $group = shift || return;
	
	my $fsdev = $c->request->params->{'device'} || return;
	my $cat = $c->request->params->{'category'} || return;
	
	#get the metrics by target
	my $targetMetrics = $c->model('Postgres')->getAggMetrics($group,$fsdev);

	my $time = time();
	my $timeZoneOffset = $time - timelocal_nocheck(gmtime($time));
	
	my %targetsByMetric;
	for my $targetMetric ( @{$targetMetrics} ) {
		my $target = $targetMetric->{'target'};
		my $metric = $targetMetric->{'metric'};
		
		unless ($targetsByMetric{$metric}) {
			$targetsByMetric{$metric} = {};
		}
		
		my $file = $RRDFILELOC . $target .'/'.$cat.'/'.$fsdev.'/'.$metric.'.rrd';
		$self->flushCacheToRrd($file);
		
		#Read in the contents of the RRD
		my $info = RRDs::info($file);
		my $step = $info->{'step'};
		
		#process each RRA (archive) in the object.
		my $rraNo = 0;
		NEWRRA:
		while ( $info->{'rra['.$rraNo.'].rows'} ) {
			my $rows   = $info->{'rra['.$rraNo.'].rows'};
			my $pdpPerRow = $info->{'rra['.$rraNo.'].pdp_per_row'};
			
			my $earliestData = $time - ($step * $pdpPerRow * $rows);
            my $periodName = 'Since '.gmtime($earliestData);
            
            unless ( $targetsByMetric{$metric}->{$earliestData} ) {
	            $targetsByMetric{$metric}->{$earliestData} = [];
			}
			
			my @plots;

			my ($start,$step,$names,$data)
				= RRDs::fetch($file, 'AVERAGE', '--start', $earliestData);
		    my $error = RRDs::error;
		    print "$error\n" if $error;

			$start += $timeZoneOffset;
			
			#if theres a max val involved for a metric, I dont want
			#go to the DB if max isnt relevant (not in the settings)
			#but I also only want to go there once. so declare the 
			#var outside the loop.
			my $max;
				
			for my $metricData ( @{$data} ) {
				#$metricData is an Array of arrays. Each inner Array
				#is the vals for each metric on a specific time slot
				
				for my $value ( @{$metricData} ) {
					push @plots, [ $start * 1000, $value ];
				}
				
				$start += $step;
			}

			push @{$targetsByMetric{$metric}->{$earliestData}},
			  { 'label' => $target, 'plots' => \@plots };
			  
			$rraNo ++;
		}
		
		$targetsByMetric{$metric}->{'settings'} = {};
		$targetsByMetric{$metric}->{'settings'}->{'fill'}  = 1;
		$targetsByMetric{$metric}->{'settings'}->{'stack'} = 1;
	}
	
    return wantarray ? %targetsByMetric : \%targetsByMetric;
}	
	

sub createRrdImage {
	my $self        = shift;
	my $c           = shift;

    #Get the GET request variables.
    my $target     = $c->request->params->{'target'};
    my $category   = $c->request->params->{'category'};
    my $device     = $c->request->params->{'device'};
    my $group      = $c->request->params->{'group'};
    my $start      = $c->request->params->{'start'}  || (48 * 3600);
    my $height     = $c->request->params->{'height'} || 280;
    my $width      = $c->request->params->{'width'}  || 730;
    
    #Calculate the start time for the graph.
    $start = time - $start;
    
    my $metrics;
    my $settings;
	my $imagefile = $STATIC_GRAPH_BASE_DIR;
	my @DEFS;
	my @CDEFS;
	my @DRAWS;
    
    #get metrics in the group
	$metrics = $c->model('Postgres')->getGroupMetrics($target,$group);
	
	#get graph group settings
	$settings = $c->model('Postgres')->getGraphGroupSettings();
	$settings = $settings->{$group};
	
	#create the file and path
    unless ( -d $imagefile ) {
		$c->response->body('Image base dir does not exist');
		return;
	}
	
    for my $path ( $target, $device ) {
		$imagefile .= $path.'/';
		unless (-d $imagefile) {
			mkdir $imagefile 
			  or $c->response->body('Could not create $imagedir')
			     and return;
	    }
	}
	$imagefile .= $group.'.png';

	#check the metric RRD files exist and ready the metric details for the graph
	my $style  = $settings->{'fill'} ? 'AREA' : 'LINE2'; 
	my $count = 0;
	
	for my $met ( @{$metrics} ) {
		my $draw;
		my $cdef;
		
		my $rrdFile = $RRDFILELOC.$target.'/'.$category.'/'.$device.'/'.$met.'.rrd';
		print "$rrdFile\n";

		unless ( -f $rrdFile ) {
			$c->response->body('The RRD file '.$rrdFile.' does not exist');
			return;
		}
		
		#if using daemon use a relative path flush the files first
		$self->flushCacheToRrd($rrdFile);
    	
    	#work out the DEFs, CDEFs and DRAWs
    	my $def  = "DEF:$met=$rrdFile:$met:AVERAGE";
		
		if ( $settings->{'mirror'} and ($count % 2) ) {
			$cdef = "CDEF:mirror$met=$met,-1,*";
			$draw = "$style:mirror$met#$COLOURS[$count]:$met";
		}
		elsif (     $settings->{'percent'} 
		        and ( my $max = $c->model('Postgres')->getMetricMax($target,$device,$met) ) ) {
			#draw as a percentage
			print "Calculating the max\n";
			$cdef = "CDEF:perc$met=$met,$max,/,100,*";
			$draw = "$style:perc$met#$COLOURS[$count]:$met";
		}
		else {
			print "No max and no mirror\n";
			$draw = "$style:$met#$COLOURS[$count]:$met";
		}
		$draw   .= ':STACK' if $settings->{'stack'};
		
		#Add them to the graph definition datas
		push @DEFS, $def;
		push @CDEFS, $cdef if $cdef;
		push @DRAWS, $draw;
		
		$count ++;
	}

    #Generate the graph.
    RRDs::graph(
        $imagefile,
        '--start'  => $start,
        '--title'  => $group,
        '--width'  => $width,
        '--height' => $height,
        @DEFS,
        @CDEFS,
        @DRAWS,
    );
    
    my $error = RRDs::error();
    if ($error) {
		print "$error\n";
		$c->response->body('Failed to create RRD graph: '.$error);
		return;
	}

    return $imagefile;
}

sub createAggRrdImage {
	my $self        = shift;
	my $c           = shift;
	my $targetGroup = shift;


    #Get the GET request variables.
    my $target     = $c->request->params->{'target'};
    my $category   = $c->request->params->{'category'};
    my $device     = $c->request->params->{'device'};
    my $metric     = $c->request->params->{'group'};
    my $start      = $c->request->params->{'start'}  || (48 * 3600);
    my $height     = $c->request->params->{'height'} || 280;
    my $width      = $c->request->params->{'width'}  || 730;
    
    #Calculate the start time for the graph.
    $start = time - $start;
    
	my $imagefile = $STATIC_GRAPH_BASE_DIR;
	my @DEFS;
	my @DRAWS;
	
	#create the image file and path
    unless ( -d $imagefile ) {
		$c->response->body('Image base dir does not exist');
		return;
	}
	
    for my $path ( $target, $device ) {
		$imagefile .= $path.'/';
		unless (-d $imagefile) {
			mkdir $imagefile 
			  or $c->response->body('Could not create $imagedir')
			     and return;
	    }
	}
	$imagefile .= $metric.'.png';


	#get Targets that have this metric and device
	my $targetsWithMetric = 
	  $c->model('Postgres')->getTargetsWithMetric($targetGroup, $device, $metric);
	
	my $count = 0;
	TARGET:
	for my $target ( @{$targetsWithMetric} ) {
		my $rrdFile = $RRDFILELOC.$target.'/'.$category.'/'.$device.'/'.$metric.'.rrd';

		unless ( -f $rrdFile ) {
			next TARGET;
		}

		#if using daemon use a relative path flush the files first
		$self->flushCacheToRrd($rrdFile);
        
       	#work out the DEFs, CDEFs and DRAWs
    	my $def   = "DEF:$count=$rrdFile:$metric:AVERAGE";
		my $draw  = "AREA:$count#$COLOURS[$count]:$target:STACK";
		
		#Add them to the graph definition datas
		push @DEFS, $def;
		push @DRAWS, $draw;

		$count ++;
	}

    #Generate the graph.
    RRDs::graph(
        $imagefile,
        '--start'  => $start,
        '--title'  => $metric,
        '--width'  => $width,
        '--height' => $height,
        @DEFS,
        @DRAWS,
    );
    
    my $error = RRDs::error();
    if ($error) {
		print "$error\n";
		$c->response->body('Failed to create RRD graph: '.$error);
		return;
	}

    return $imagefile;
}
	
#INTERNAL SUBS

sub flushCacheToRrd {
	my $self;
	my $file || return;
	
	if ($RRDCACHED_ADDR) {
		my $relativeFile = $file;
		$relativeFile =~ s/^$RRDFILELOC//;
		RRDs::flushcached($relativeFile, '--daemon', $RRDCACHED_ADDR);
		my $error = RRDs::error;
	    print "RRD ERROR: $error\n" if $error;
	}

    return 1;
}


1;
