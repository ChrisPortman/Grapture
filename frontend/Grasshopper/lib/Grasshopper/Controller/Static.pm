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



=head1 AUTHOR

Chris Portman

=head1 LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

__PACKAGE__->meta->make_immutable;

1;
