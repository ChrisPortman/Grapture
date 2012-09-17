package Grapture::Controller::Usermgmt;
use Moose;
use namespace::autoclean;

BEGIN {extends 'Catalyst::Controller::REST'; }

__PACKAGE__->config( 'map'     => {'text/html' => 'JSON'} );
__PACKAGE__->config( 'default' => 'application/json'      );

=head1 NAME

Grapture::Controller::Usermgmt - Catalyst Controller

=head1 DESCRIPTION

Catalyst Controller.

=head1 METHODS

=cut

sub login : Local : ActionClass('REST') {}

sub login_POST {
	my ($self, $c) = @_;
	
	my $username = $c->request->params->{'username'};
	my $password = $c->request->params->{'password'};
	
	my $login = $c->model('Postgres')->checkUserLogin($username, $password);
	
	if ($login) {
		# Successfull
		$c->session->{'loggedIn'} = 1;
		
		$self->status_ok(
		    $c,
		    entity => { 'success' => 1, 'data' => 'Welcome '.$username },
	    );
	}
	else {
		# Failed
		$self->status_ok(
		    $c,
		    entity => { 'success' => undef, 'data' => 'Login Failed' },
	    );
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
