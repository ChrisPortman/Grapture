package Grasshopper::Model::RRDTool;
use Moose;
use namespace::autoclean;

use RRDs;
use Time::Local qw(timelocal_nocheck timegm_nocheck);
use Data::Dumper;

extends 'Catalyst::Model';

=head1 NAME

Grasshopper::Model::RRDTool - Catalyst Model

=head1 DESCRIPTION

Catalyst Model.

=head1 AUTHOR

Chris Portman

=head1 LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

__PACKAGE__->meta->make_immutable;

my $RRDFILELOC            = $Grasshopper::GHCONFIG->{'DIR_RRD'};
my $STATIC_GRAPH_BASE_DIR = $Grasshopper::GHCONFIG->{'STATIC_GRAPH'};
my $RRDCACHED_ADDR        = $Grasshopper::GHCONFIG->{'RRD_BIND_ADDR'};
$RRDFILELOC               =~ s|([^/])$|$1/|;
$STATIC_GRAPH_BASE_DIR    =~ s|([^/])$|$1/|;

#Blue Red  Green Yellow Pink Peach DGreen Ivory Lavendar
my @COLOURS = qw( a8d0d8 eabcbf bddcb3 
                  f2de7d ddadbd efc5ac 
                  a4ce9e f3e3bf d7c3cf);


sub readRrdDir {
	#suck in all the RRDS in $dir and extract all the metric data.
    my $self   = shift;
    my $c      = shift;
    my $target = shift;
    my $cat    = shift;
    my $fsdev  = shift;
    
    my %metricGroups;
    my %objsByGroups;
    my $dev = $fsdev;
    $dev =~ s|_SLSH_|/|g;
    
    my $dir = $RRDFILELOC . $target .'/'.$cat.'/'.$fsdev;
    unless ( -d $dir ) {
		print "no directory $dir\n";
		$self->status_no_content($c);
		return 1;
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
			if ($RRDCACHED_ADDR) {
				my $relativeFile = $file;
				$relativeFile =~ s/^$RRDFILELOC//;
				RRDs::flushcached($relativeFile, '--daemon', $RRDCACHED_ADDR);
				my $error = RRDs::error;
			    print "RRD ERROR: $error\n" if $error;
			}
			
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
	            
	            unless ( $objsByGroups{$group}->{$earliestData} ) {
		            $objsByGroups{$group}->{$earliestData} = [];
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

sub createRrdImage {
	my $self   = shift;
	my $c      = shift;	

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
		if ($RRDCACHED_ADDR) {
			my $relativeRrd = $rrdFile;
			$relativeRrd =~ s/^$RRDFILELOC//;
			RRDs::flushcached($relativeRrd, '--daemon', $RRDCACHED_ADDR);
			my $error = RRDs::error;
		    print "RRD ERROR: $error\n" if $error;
		}
    	
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

    #~ ($imagefile) = $imagefile =~ m|/([^/]+)$|;
    return $imagefile;
}

1;
