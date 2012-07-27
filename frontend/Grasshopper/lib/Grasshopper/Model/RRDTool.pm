package Grasshopper::Model::RRDTool;
use Moose;
use namespace::autoclean;

use RRDs;
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
    
    my %objsByGroups;

	my $time = time();
    
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
		
		DATAS:
		for my $ds ( keys %{$objsByGroups{$group}} ) {
			my $file = $objsByGroups{$group}->{$ds};
			
			my $info = RRDs::info($file);
			my $step = $info->{'step'};
            
            delete $objsByGroups{$group}->{$ds};
            		
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

                for my $metricData ( @{$data} ) {
					#$metricData is an Array of arrays. Each inner Array
					#is the vals for each metric on a specific time slot
					for my $value ( @{$metricData} ) {
						push @plots, [ $start * 1000, $value ];
					}

					$start += $step;
				}

				push @{$objsByGroups{$group}->{$earliestData}},
				  { 'label' => $ds, 'plots' => \@plots };
				  
				$rraNo ++;
			}
		}
	}

    return wantarray ? %objsByGroups : \%objsByGroups;
}

1;
