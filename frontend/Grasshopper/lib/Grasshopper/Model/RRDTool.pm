package Grasshopper::Model::RRDTool;
use Moose;
use namespace::autoclean;

use RRDTool::OO;
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
my $RRDHTMLLOC = '/static/rrddata/';
$RRDFILELOC =~ s|([^/])$|$1/|;
$RRDHTMLLOC =~ s|([^/])$|$1/|;

my $GPH_BASE_DIR = '/home/chris/git/Grasshopper/frontend/Grasshopper/root/static/rrds/';
my $IMAGE_HEIGHT = 200;
my $IMAGE_WIDTH  = 700;


sub graph {
	my $self = shift;
	my ($target, $category, $device) = @_;
	
	unless ($target and $category and $device) {
		print "invalid args\n";
		return;
	}
		
	my $rrdFile = $RRDFILELOC.$target.'/'.$category.'/'.$device.'.rrd';
	
	unless ( -f $rrdFile ) {
		print "rrd file $rrdFile not present\n";
		return;
	}
	
	my $rrdObj  = RRDTool::OO->new( 'file' => $rrdFile )
	  or return;
	my $rrdInfo = $rrdObj->info();
		
	#get Archive settings
	my $archives    = $self->getRrdArchives($rrdInfo);
	my $dataSources = $self->getRrdSources($rrdInfo);
	
	my @images;
	my $count = 1;
	for my $archive ( @{$archives} ) {
    	my @draws;
    	my $image = $GPH_BASE_DIR.$target.'.'.$device.$count.'.png';

		for my $ds ( keys %{$dataSources} ) {
			push @draws, ( 'draw' => {
				'type'      => 'line',
				'dsname'    => $ds,
				'thickness' => 1,
				'cfunc'     => 'AVERAGE',
				'legend'    => $ds,
			} );
		}
		
		$rrdObj->graph(
		    'image'  => $image,
		    'start'  => time() - $archive->{'period'},
		    'end'    => time(),
		    'height' => $IMAGE_HEIGHT,
		    'width'  => $IMAGE_WIDTH,
		    'units'  => 'si',
		    @draws,
		)
		  or next;
		
		unless ( -f $image ) {
			print "ARG! the image file doesnt exist yet!\n";
		}
		
		$image =~ s|/.+/||;
		$image = '/static/rrds/'.$image;
		
		push @images, { 'title'  => $archive->{'textPeriod'},
		                'url'    => $image,
		              };
		$count ++;
	}
	
	return wantarray ? @images : \@images;
}

sub getRrdArchives {
    my $self = shift;
    my $info = shift;
    
    my %secondsIn = ( 'min'   => 60,
                      'hour'  => 3600,
                      'day'   => 86400,
                      'week'  => 604800,
                      'month' => 2592000,
                      'year'  => 31104000,
                    );
    
    #Step is number of secs between samples
    my $step = $info->{'step'};
    my @rras;
    
    for my $rra ( @{$info->{'rra'}} ) {
		my $rows          = $rra->{'rows'};
		my $summerisation = $rra->{'pdp_per_row'};
		
		#number of seconds into the past this rra extends
		my $period = $step * $summerisation * $rows;
		
		$period or next;
		
		my $textPeriod;
		if ( (my $years = int($period / $secondsIn{'year'})) > 1 ) {

			$textPeriod = "$years Years";
			if ( my $remain = $period % $secondsIn{'year'} ) {

				if ( $remain > $secondsIn{'month'} ) {

					my $months = int($remain / $secondsIn{'month'});
					$textPeriod .= ' '.$months.' Months';
					
				}
			}
		}
		elsif ( (my $months = int($period / $secondsIn{'month'})) > 1 ) {

			$textPeriod = "$months Months";
			if ( my $remain = $period % $secondsIn{'month'} ) {

				if ( $remain > $secondsIn{'week'} ) {

					my $weeks = int($remain / $secondsIn{'week'});
					$textPeriod .= ' '.$weeks.' Weeks';
					
				}
			}
		}
		elsif ( (my $weeks = int($period / $secondsIn{'week'})) > 1 ) {

			$textPeriod = "$weeks Weeks";
			if ( my $remain = $period % $secondsIn{'week'} ) {

				if ( $remain > $secondsIn{'day'} ) {

					my $days = int($remain / $secondsIn{'day'});
					$textPeriod .= ' '.$days.' Days';
					
				}
			}
		}
		elsif ( (my $days = int($period / $secondsIn{'day'})) > 1 ) {

			$textPeriod = "$days Days";
			if ( my $remain = $period % $secondsIn{'day'} ) {

				if ( $remain > $secondsIn{'hour'} ) {

					my $hours = int($remain / $secondsIn{'hour'});
					$textPeriod .= ' '.$hours.' Hours';
					
				}
			}
		}
		elsif ( (my $hours = int($period / $secondsIn{'hour'})) > 1 ) {
			$textPeriod = "$hours Hours";
		}
		else {
			return;
		}
		
		push @rras, { 'period'     => $period,
		              'textPeriod' => $textPeriod,
				    };
    }
    
    @rras = sort { $a->{'period'} <=> $b->{'period'} } @rras;
    
    return wantarray ? @rras : \@rras;
}

sub getRrdSources {
	my $self = shift;
	my $info = shift;
	
	my $datas = $info->{'ds'};
	
	return wantarray ? %{$datas} : $datas;
}

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

    my @rrdFiles = map { $dir.'/'.$_ } #Prepend the full path.
                   grep { m/\.rrd$/ }  #keep the *.rrd files.
                   readdir($dh);

    closedir $dh;
    
    my %objsByGroups;

	my $time = time();
    
    for my $rrd (@rrdFiles) {
		# Go through each RRD file and work out what data sources they 
		# have and what groups the data sources belong to.
	    
		next unless -f $rrd;
		my $rrdObj = RRDTool::OO->new( 'file'        => $rrd,
		                               'raise_error' => 0 
		) or next;
		
		my @dataSources = keys $rrdObj->info()->{'ds'};
		
		for my $ds ( @dataSources ) {
			my $group = $c->model('Postgres')->getMetricGrp($target, $dev, $ds)
			            || $ds;

			unless ( $objsByGroups{$group} ) {
				$objsByGroups{$group} = {};
			}
			
			$objsByGroups{$group}->{$ds} = $rrdObj;
		}
	}
	
	GROUPS:
	for my $group ( keys %objsByGroups ) {
		
		DATAS:
		for my $ds ( keys %{$objsByGroups{$group}} ) {
		
			my $obj  = $objsByGroups{$group}->{$ds};
			my $info = $obj->info();
            my $step = $info->{'step'};
            
            delete $objsByGroups{$group}->{$ds};
            		
			#process each RRA (archive) in the object.
			RRA:
			for my $rra ( @{$info->{'rra'}} ) {
				my $rows      = $rra->{'rows'};
				my $pdpPerRow = $rra->{'pdp_per_row'};

	            my $earliestData = $time - ($step * $pdpPerRow * $rows);
	            my $periodName = 'Since '.gmtime($earliestData);
	            
	            unless ( $objsByGroups{$group}->{$earliestData} ) {
		            $objsByGroups{$group}->{$earliestData} = [];
				}

				my @plots;
				$obj->fetch_start( 'start' => $earliestData, );
				while ( my ($time, $value) = $obj->fetch_next() ) {
					push @plots, [ $time * 1000, $value ];
				}

				push @{$objsByGroups{$group}->{$earliestData}},
				  { 'label' => $ds, 'plots' => \@plots };
			}
			
		}
	}

    return wantarray ? %objsByGroups : \%objsByGroups;
}

sub getRrdInfo {
	# get an RRDs meta data.
	my $self   = shift;
	my $c      = shift;
	my $target = shift;
	my $cat    = shift;
	my $dev    = shift;
	
	my $dir = $RRDFILELOC . $target .'/'.$cat.'/'.$dev;
	
	unless ( -d $dir ) {
		$self->status_no_content($c);
		return 1;
	}

	opendir (my $dh, $dir)
	  or $self->status_no_content($c) and return 1;

    my @rrdFiles = map { $dir.'/'.$_ } #Prepend the full path.
                   grep { m/\.rrd$/ }  #keep the *.rrd files.
                   readdir($dh);

    closedir $dh;
	
	#get the info for each file.
    my @graphs;
    for my $rrd (@rrdFiles) {
		next unless -f $rrd;
		
		my $rrdObj = RRDTool::OO->new( 'file'        => $rrd,
		                               'raise_error' => 0 
		                             )
		  or next;
		
		my $info = $rrdObj->info();
		
		#swap the full path of filename with the HTML loction
		$info->{'filename'} =~ s/$RRDFILELOC/$RRDHTMLLOC/e;
		
		#the ds key in info holds a ref to a hash keyed on the store
		#name.  this needs to be translated to an array of hash refs
		#So, take the store name, add it to a 'name' key inside the stores
		#hash and add each store to an array then make the array the value
		#of 'ds'.
		my %dataStores = %{$info->{'ds'}};
		
		for my $ds ( keys %dataStores ) {
			$dataStores{$ds}->{'name'}  = $ds;
			$info->{'group'} = 
			  $c->model('Postgres')->getMetricGrp($target, $dev, $ds)
			  || undef;
						
			unless ( ref($info->{'ds'}) and ref($info->{'ds'}) eq 'ARRAY') {
				$info->{'ds'} = [];
			}
			
			push @{$info->{'ds'}}, $dataStores{$ds};
		}
		
        push @graphs, $info;
	}
	
	return wantarray ? @graphs : \@graphs;
}


1;
