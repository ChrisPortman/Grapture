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

my $RRD_BASE_DIR = '/home/chris/git/Grasshopper/rrds';
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
		
	my $rrdFile = $RRD_BASE_DIR.$target.'/'.$category.'/'.$device.'.rrd';
	
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


1;
