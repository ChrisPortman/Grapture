package Grapture::Controller::Rest;
use Moose;
use namespace::autoclean;

use Data::Dumper;

BEGIN {extends 'Catalyst::Controller::REST'; }

__PACKAGE__->config( 'map'     => {'text/html' => 'JSON'} );
__PACKAGE__->config( 'default' => 'application/json'      );

my $RRDFILELOC = $Grapture::GHCONFIG->{'DIR_RRD'};
$RRDFILELOC =~ s|([^/])$|$1/|;

=head1 NAME

Grapture::Controller::Rest - Catalyst Controller

=head1 DESCRIPTION

Catalyst Controller.

=head1 METHODS

=cut
#Target info
sub targets       : Local : ActionClass('REST') {}
sub targetcats    : Local : ActionClass('REST') {}
sub targetconfig  : Local : ActionClass('REST') {}
sub targetdevices : Local : ActionClass('REST') {}

#Graph data
sub graphs        : Local : ActionClass('REST') {}
sub graphdetails  : Local : ActionClass('REST') {}
sub graphdata     : Local : ActionClass('REST') {}

#CRUD
sub addhost       : Local : ActionClass('REST') {}
sub edithost      : Local : ActionClass('REST') {}
sub addgroup      : Local : ActionClass('REST') {}


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
	my ($self, $c) = @_;
    my %objsByGroups;

    if ( $c->request->params->{'target'} =~ /^(.+)_Aggregates/ ){
		my $group = $1;
		%objsByGroups = $c->model('RRDTool')->getAggRrdData($c, $group);
	}
	else {
	    %objsByGroups = $c->model('RRDTool')->getRrdData($c);
	}
		
	unless ( %objsByGroups ) {
		$self->status_no_content($c);
		return 1;
	}
    
	$self->status_ok(
	    $c,
	    entity => { 'success' => 'true', 'data' => \%objsByGroups },
    );
}

sub addhost_POST {
	my ($self, $c) = @_;
	
	my ($success, $message) = $c->model('Postgres')->addHosts($c);

    $message ||= 'An unknown error occured';	
	
	$self->status_created(
		$c,
		location => $c->req->uri,
		entity => {
			'success' => $success,
			'data'    => $message,
		}
	);
}

sub edithost_POST {
	my ($self, $c) = @_;
	
	my ($success, $message) = $c->model('Postgres')->editHost($c);

    $message ||= 'An unknown error occured';	
	
	$self->status_created(
		$c,
		location => $c->req->uri,
		entity => {
			'success' => $success,
			'data'     => $message,
		}
	);
}

sub addgroup_POST {
	my ($self, $c) = @_;
	
	my ($success, $message) = $c->model('Postgres')->addGroup($c);

    $message ||= 'An unknown error occured';	
	
	$self->status_created(
		$c,
		location => $c->req->uri,
		entity => {
			'success' => $success,
			'data'     => $message,
		}
	);
}

sub targetconfig_GET {
	my ($self, $c) = @_;
	my $status;
	
	my $config = $c->model('Postgres')->getTargetConfig($c);
	$status = 1 if $config;

	$self->status_ok(
	    $c,
	    entity => { 'success' => $status, 'data' => $config },
    );
}

sub auto :Private {
    my ( $self, $c ) = @_;
    
    #any APIs that except new data can only be used by authenticated clients.
    if ($c->request->method eq 'POST') {
	    unless ( $c->session->{'loggedIn'} ) {
			$self->status_ok(
			    $c,
			    entity => { 'success' => undef, 'data' => 'Not logged in' },
		    );
		    return;
		}
	}
	
	return 1;
}


=head1 AUTHOR

Chris Portman

=head1 LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

__PACKAGE__->meta->make_immutable;

1;
