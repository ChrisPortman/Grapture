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
$RRDFILELOC =~ s|([^/])$|$1/|;

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

1;
