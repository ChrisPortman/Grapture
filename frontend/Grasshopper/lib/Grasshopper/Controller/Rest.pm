package Grasshopper::Controller::Rest;
use Moose;
use namespace::autoclean;

use Data::Dumper;
use RRDTool::OO;

BEGIN {extends 'Catalyst::Controller::REST'; }

__PACKAGE__->config( 'map'     => {'text/html' => 'JSON'} );
__PACKAGE__->config( 'default' => 'application/json'      );

my $RRDFILELOC = $Grasshopper::GHCONFIG->{'DIR_RRD'};
$RRDFILELOC =~ s|([^/])$|$1/|;

=head1 NAME

Grasshopper::Controller::Rest - Catalyst Controller

=head1 DESCRIPTION

Catalyst Controller.

=head1 METHODS

=cut
sub targets       : Local : ActionClass('REST') {}
sub targetcats    : Local : ActionClass('REST') {}
sub targetdevices : Local : ActionClass('REST') {}
sub graphs        : Local : ActionClass('REST') {}
sub graphdetails  : Local : ActionClass('REST') {}
sub graphdata     : Local : ActionClass('REST') {}

sub targets_GET {
	my ($self, $c) = @_;
	my $tree = $c->model('Postgres')->getTargetTree;
	
	$self->status_ok(
	    $c,
	    entity => $tree,
	);
}

sub targetcats_GET {
	my ($self, $c, $target) = @_;
	
	unless ( $target ) {
		$self->status_no_content($c);
		return 1;
    }
	
	my $categories = $c->model('Postgres')->getTargetCats($target);
	
	unless ( scalar @{$categories} ) {
		$self->status_no_content($c);
		return 1;
	}
	
	$self->status_ok(
	    $c,
	    entity => $categories,
    );
}

sub targetdevices_GET {
	my ($self, $c, $target, $cat) = @_;
	
	unless ( $target and $cat ){
		$self->status_no_content($c);
		return 1;
    }
	
	my $devices = $c->model('Postgres')->getTargetDevs($c, $target, $cat);
	
	unless ( scalar @{$devices} ) {
		$self->status_no_content($c);
		return 1;
	}
	
	$self->status_ok(
	    $c,
	    entity => $devices,
    );
}

sub graphs_GET {
	my ($self, $c, $target, $cat, $dev) = @_;
	
	print "$target, $cat, $dev\n";
	
	my $graphs = $c->model('RRDTool')->graph($target, $cat, $dev);

	print Dumper($graphs);


	$self->status_ok(
	    $c,
	    entity => $graphs,
    );
}

sub graphdetails_GET {
	my ($self, $c, $target, $cat, $dev) = @_;
	
	unless ( $target and $cat and $dev ) {
		$self->status_no_content($c);
		return 1;
	}

    my @graphs = $c->model('RRDTool')->getRrdInfo($c, $target, $cat, $dev);

	unless ( scalar(@graphs) ) {
		$self->status_no_content($c);
		return 1;
	}
    
	$self->status_ok(
	    $c,
	    entity => { 'success' => 'true', 'rrds' => \@graphs },
    );
}

sub graphdata_GET {
	my ($self, $c, $target, $cat, $dev) = @_;
	
		unless ( $target and $cat and $dev ) {
		$self->status_no_content($c);
		return 1;
	}
	
	my %objsByGroups = $c->model('RRDTool')->readRrdDir($c, $target, $cat, $dev);
		
	unless ( %objsByGroups ) {
		$self->status_no_content($c);
		return 1;
	}
    
	$self->status_ok(
	    $c,
	    entity => { 'success' => 'true', 'data' => \%objsByGroups },
    );
}

=head1 AUTHOR

Chris Portman

=head1 LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

__PACKAGE__->meta->make_immutable;

1;
