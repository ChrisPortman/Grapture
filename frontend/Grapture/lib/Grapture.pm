package Grapture;
use Moose;
use namespace::autoclean;

use Catalyst::Runtime 5.80;
use Grapture::Common::Config;

# Set flags and add plugins for the application.
#
# Note that ORDERING IS IMPORTANT here as plugins are initialized in order,
# therefore you almost certainly want to keep ConfigLoader at the head of the
# list if you're using it.
#
#         -Debug: activates the debug mode for very useful log messages
#   ConfigLoader: will load the configuration from a Config::General file in the
#                 application's home directory
# Static::Simple: will serve static files from the application's root
#                 directory

use Catalyst qw/
    -Debug
    ConfigLoader
    Static::Simple
    Session
    Session::Store::FastMmap
    Session::State::Cookie
/;


extends 'Catalyst';

our $VERSION = '0.01';

# Configure the application.
#
# Note that settings in grapture.conf (or other external
# configuration file that you set up manually) take precedence
# over this when using ConfigLoader. Thus configuration
# details given here can function as a default configuration,
# with an external configuration file acting as an override for
# local deployment.

sub getConfig {
	my $cfgFile = shift;
	
	unless ($cfgFile and -f $cfgFile) {
		return;
	}
    
    my $configObj = Grapture::Common::Config->new($cfgFile);
    my $config = $configObj->getAllConfig();
	
	return $config;
}

my $configFile = '../../etc/grapture.cfg';
our $GHCONFIG = getConfig( $configFile );

__PACKAGE__->config(
    name => 'Grapture',
    # Disable deprecated behavior needed by old applications
    disable_component_resolution_regex_fallback => 1,
    enable_catalyst_header => 1, # Send X-Catalyst header
);

# Start the application
__PACKAGE__->setup();


=head1 NAME

Grapture - Catalyst based application

=head1 SYNOPSIS

    script/grapture_server.pl

=head1 DESCRIPTION

[enter your description here]

=head1 SEE ALSO

L<Grapture::Controller::Root>, L<Catalyst>

=head1 AUTHOR

Chris Portman

=head1 LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
