package Grasshopper::Controller::Static;
use Moose;
use namespace::autoclean;

use Chart::Clicker;
use Chart::Clicker::Data::Series;
use Chart::Clicker::Data::DataSet;
use Chart::Clicker::Renderer::Area;


BEGIN {extends 'Catalyst::Controller'; }

=head1 NAME

Grasshopper::Controller::Static - Catalyst Controller

=head1 DESCRIPTION

Catalyst Controller.

=head1 METHODS

=cut


=head2 index

=cut

sub index :Path :Args(0) {
    my ( $self, $c ) = @_;
    
    #Get the GET request variables.
    my $target;
    my $category;
    my $device;
    my $graphGroup;
    my $rra;
    
    #Get the RRD data for the graphs
    my $rrdData = $c->model('RRDTool')->readRrdDir($c, $target, $cat, $dev);
    
    #Mangle data into a format usable by Chart Clicker.
    
    #Produce the graphs
    
    #Send to a view to display the raw image (not image in html).
    

    $c->response->body('Matched Grasshopper::Controller::Static in Static.');
}


=head1 AUTHOR

Chris Portman

=head1 LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

__PACKAGE__->meta->make_immutable;

1;
