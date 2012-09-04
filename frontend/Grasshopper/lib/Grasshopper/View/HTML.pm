package Grasshopper::View::HTML;
use Moose;
use namespace::autoclean;

extends 'Catalyst::View::TT';

__PACKAGE__->config(
    TEMPLATE_EXTENSION => '.tt',
#    WRAPPER            => 'wrapper.tt',
    render_die => 1,
);

=head1 NAME

Grasshopper::View::HTML - TT View for Grasshopper

=head1 DESCRIPTION

TT View for Grasshopper.

=head1 SEE ALSO

L<Grasshopper>

=head1 AUTHOR

Chris Portman

=head1 LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
