package Grasshopper::Controller::Static;
use Moose;
use namespace::autoclean;

use Chart::Clicker;
use Chart::Clicker::Data::Series;
use Chart::Clicker::Data::DataSet;
use Chart::Clicker::Axis::DateTime;
use Chart::Clicker::Renderer::Area;
use Chart::Clicker::Renderer::StackedArea;

use Data::Dumper;


BEGIN {extends 'Catalyst::Controller'; }

=head1 NAME

Grasshopper::Controller::Static - Catalyst Controller

=head1 DESCRIPTION

Catalyst Controller.

=head1 METHODS

=cut


=head2 index

=cut
#FIXME: Get from config file.
my $STATIC_GRAPH_BASE_DIR = '/home/chris/git/Grasshopper/frontend/Grasshopper/root/graphs';
$STATIC_GRAPH_BASE_DIR =~ s|([^/])$|$1/|;

sub index :Path :Args(0) {
    my ( $self, $c ) = @_;
    my $rrdData; #all RRAs
    my $rraData; #just the relevant RRA
    my $settings;
    my @series;
    
    #Get the GET request variables.
    my $target     = $c->request->params->{'target'};
    my $category   = $c->request->params->{'category'};
    my $device     = $c->request->params->{'device'};
    my $graphGroup = $c->request->params->{'group'};
    my $start      = $c->request->params->{'start'};
    my $height     = $c->request->params->{'height'} || 280;
    my $width      = $c->request->params->{'width'}  || 730;
    
    unless ($target and $category and $device and $graphGroup){
		$c->response->body('Missing requried parameters');
		return 1;
	}
    my $time = time;
    
    #Get the RRD data for the graphs
    $rrdData = $c->model('RRDTool')->readRrdDir($c, $target, $category, $device);
    $rrdData = $rrdData->{$graphGroup};
    
    print 'Got RRD Dump in '. (time - $time)."\n";

	#Stash the settings
	$settings = delete $rrdData->{'settings'};
    
    $time = time;
    #Get just the relevant rra.
    for my $earliest (reverse sort keys %{$rrdData} ) {
		#If we dont have a start, use the shortest/highest res
		if (not $start or ($earliest <= $start)) {
			$rraData	= $rrdData->{$earliest};
			last;
		}
		else {
			#This allows us to default to the longest RRA if the start is
			#before the scope of even the longest RRA.
			$rraData = $rrdData->{$earliest};
		}
	}
    print 'Determined the RRA in '. (time - $time)."\n";

    $time = time;
    #Mangle data into a format usable by Chart Clicker.
    for my $idx ( 0..$#{$rraData} ) {
		
		for my $plot ( @{$rraData->[$idx]->{'plots'}} ) {
		
			$rraData->[$idx]->{'keys'} = [] 
			  unless $rraData->[$idx]->{'keys'};
			$rraData->[$idx]->{'vals'} = [] 
			  unless $rraData->[$idx]->{'vals'};
			  
			my $key = $plot->[0] ? $plot->[0] / 1000 : 0;
			my $val = $plot->[1] || 0;
			
		    push @{$rraData->[$idx]->{'keys'}}, $key;
			push @{$rraData->[$idx]->{'vals'}}, $val;
		}
		delete $rraData->[$idx]->{'plots'};

		push @series, Chart::Clicker::Data::Series->new(
		    {
				'name'   => $rraData->[$idx]->{'label'},
				'keys'   => $rraData->[$idx]->{'keys'},
				'values' => $rraData->[$idx]->{'vals'}, 
			}
	    );
	}
    print 'Built the series in '. (time - $time)."\n";

    
    #Set up the directory (the base must pre exist)
    my $imagedir = $STATIC_GRAPH_BASE_DIR;
    unless ( -d $imagedir ) {
		$c->response->body('Image base dir does not exist');
		return 1;
	}
	
    for my $path ( $target, $device ) {
		$imagedir .= $path.'/';
		unless (-d $imagedir) {
			mkdir $imagedir 
			  or $c->response->body('Could not create $imagedir')
			     and return 1;
	    }
	}
    
    $time = time;
    #Produce the graphs
    my $chart = Chart::Clicker->new();
    $chart->title->text($graphGroup);
    $chart->title->padding->bottom(10);
    $chart->height($height);
    $chart->width($width);

    my $ctx = $chart->get_context('default');
    $ctx->domain_axis(Chart::Clicker::Axis::DateTime->new(
	    'position'    => 'bottom',
	    'orientation' => 'horizontal',
	    'format'      => '%d/%m/%Y %H:%M',
	    'staggered'   => 1,
	));
    
    my $dataset = Chart::Clicker::Data::DataSet->new(
        'series'  => \@series,
    );
    $chart->add_to_datasets($dataset);
    
    #Render the plots according to the settings
    my $renderer;
    if ( $settings->{'fill'} ) {
		print "Using Fill\n";
	    $renderer = Chart::Clicker::Renderer::Area->new(
	        'opacity' => .50,
	    );
	}
	if ( $settings->{'stack'} ) {
		print "Using Stack\n";
	    $renderer = Chart::Clicker::Renderer::StackedArea->new(
	        'opacity' => .50,
	    );
    }
    $chart->set_renderer($renderer) if $renderer;
        
    $chart->write_output( $imagedir.$graphGroup.'.png' );
    print 'Created the graph in '. (time - $time)."\n";

    
    #Send to a view to display the raw image (not image in html).
    $c->response->body('Graph created');
}

sub rrd :Local :Args() {
	my ( $self, $c ) = @_;
    
	my $rrdfile = $c->model('RRDTool')->createRrdImage($c);
	
	if ($rrdfile) {
		if (open my $image, '<', $rrdfile) {
			$c->response->headers->content_type('image/png');
		    $c->response->body($image);
		}
		else {
			$c->response->body('Could not open image file');
		}
	}
		
}


sub formatTime :Private {
	my $time = shift or return;
	
	my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) =
      localtime($time);
    
    $year += 1900;
    $mon  += 1;
    
    return $mday.'/'.$mon.'/'.$year.' '.$hour.':'.$min;
}
	
	



=head1 AUTHOR

Chris Portman

=head1 LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

__PACKAGE__->meta->make_immutable;

1;
