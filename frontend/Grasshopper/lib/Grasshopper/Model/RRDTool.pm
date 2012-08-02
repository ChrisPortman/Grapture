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

my $RRDFILELOC = $Grasshopper::GHCONFIG->{'DIR_RRD'};
my $STATIC_GRAPH_BASE_DIR = '/home/chris/git/Grasshopper/frontend/Grasshopper/root/graphs';
$RRDFILELOC =~ s|([^/])$|$1/|;
$STATIC_GRAPH_BASE_DIR =~ s|([^/])$|$1/|;

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
    my $dev    = shift;
    
    my $dir = $RRDFILELOC . $target .'/'.$cat.'/'.$dev;
	
	unless ( -d $dir ) {
		print "no directory $dir\n";
		$self->status_no_content($c);
		return 1;
	}

	opendir (my $dh, $dir)
	  or $self->status_no_content($c) and return 1;

    my @rrdFiles = map  { $dir.'/'.$_ } #Prepend the full path.
                   grep { m/\.rrd$/   } #keep the *.rrd files.
                   readdir($dh);

    closedir $dh;
    
    
    my $graphGroupSettings = $c->model('Postgres')->getGraphGroupSettings(); 
    my %objsByGroups;
	my $time = time();
	my $timeZoneOffset = $time - timelocal_nocheck(gmtime($time));
	
    for my $rrd (@rrdFiles) {
		# Go through each RRD file and work out what data sources they 
		# have and what groups the data sources belong to.
	    
		next unless -f $rrd;
		
		my %dataSources = map { m/\[(.+)\]/; $1 => 1; }
		                  grep { /^ds/ }
		                  keys %{ RRDs::info($rrd) };
		
		for my $ds ( keys %dataSources ) {
			my $group = $c->model('Postgres')->getMetricGrp($target, $dev, $ds)
			            || $ds;

			unless ( $objsByGroups{$group} ) {
				$objsByGroups{$group} = {};
			}
			
			$objsByGroups{$group}->{$ds} = $rrd;
		}
	}
	
	GROUPS:
	for my $group ( keys %objsByGroups ) {
		
		my $dsCounter = 0;
		DATAS:
		for my $ds ( keys %{$objsByGroups{$group}} ) {
			my $file = delete $objsByGroups{$group}->{$ds};
			
			my $info = RRDs::info($file);
			my $step = $info->{'step'};
            
			#process each RRA (archive) in the object.
			NEWRRA:
			my $rraNo = 0;
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
                
				#store a cumulative sum so we can get the ds average
				my $sum;
				my $count;
					
                for my $metricData ( @{$data} ) {
					#$metricData is an Array of arrays. Each inner Array
					#is the vals for each metric on a specific time slot
					
					for my $value ( @{$metricData} ) {
						if ($value) {
							if ( $graphGroupSettings->{$group}->{'mirror'} 
							     and ($dsCounter % 2) ) {
							    $value = -$value;
							}
						    $sum += $value;
						    $count ++;
						}
						push @plots, [ $start * 1000, $value ];
					}
					
					$start += $step;
				}

				#add the average as the last element, we'll sort on
				#it and remove it later
				if ($sum and $count) {
					my $avg = $sum / $count;
					push @plots, $avg;
				}
				else {
					push @plots, 0;
				}

				push @{$objsByGroups{$group}->{$earliestData}},
				  { 'label' => $ds, 'plots' => \@plots };
				  
				$rraNo ++;
			}

			$dsCounter ++;
		}
		
		#Sort the metrics within the group on their average
		#Order depends on whether the graph is to be stacked or
		#not.
		for my $rra ( keys %{$objsByGroups{$group}} ) {
			next unless ref $objsByGroups{$group}->{$rra};
			
			if ( $graphGroupSettings->{$group}->{'stack'} ) {
				#Sort on Average ascending
				@{$objsByGroups{$group}->{$rra}} = sort
				    { $a->{'plots'}->[-1] <=> $b->{'plots'}->[-1] }
				    @{$objsByGroups{$group}->{$rra}};
			}
			else {
				#Sort on Average decending
				@{$objsByGroups{$group}->{$rra}} = sort
				    { $b->{'plots'}->[-1] <=> $a->{'plots'}->[-1] }
				    @{$objsByGroups{$group}->{$rra}};
			}
			#remove the averages
			for (@{$objsByGroups{$group}->{$rra}}) {
				pop @{$_->{'plots'}};
			}
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
    my $start      = $c->request->params->{'start'}  || (time - (48 * 3600));
    my $height     = $c->request->params->{'height'} || 280;
    my $width      = $c->request->params->{'width'}  || 730;
    
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
	my $style  = $settings->{'fill'} ? 'AREA' : 'LINE'; 
	my $count = 0;
	
	for my $met ( @{$metrics} ) {
		my $draw;
		my $cdef;
		
		my $rrdfile = $RRDFILELOC.$target.'/'.$category.'/'.$device.'/'.$met.'.rrd';
		print "$rrdfile\n";

		unless ( -f $rrdfile ) {
			$c->response->body('The RRD file '.$rrdfile.' does not exist');
			return;
		}
		
		my $def  = "DEF:$met=$rrdfile:$met:AVERAGE";
		
		if ( $settings->{'mirror'} and ($count % 2) ) {
			$cdef = "CDEF:c$met=$met,-1,*";
			
			$draw = "$style:c$met#$COLOURS[$count]:$met";
			$draw   .= ':STACK' if $settings->{'stack'};
		}
		else {
			$draw = "$style:$met#$COLOURS[$count]:$met";
			$draw   .= ':STACK' if $settings->{'stack'};
		}
		
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
