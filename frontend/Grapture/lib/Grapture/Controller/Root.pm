package Grapture::Controller::Root;
use Moose;
use namespace::autoclean;

use Data::Dumper;

BEGIN { extends 'Catalyst::Controller' }

#
# Sets the actions in this controller to be registered with no prefix
# so they function identically to actions created in MyApp.pm
#
__PACKAGE__->config(namespace => '');

=head1 NAME

Grapture::Controller::Root - Root Controller for Grapture

=head1 DESCRIPTION

[enter your description here]

=head1 METHODS

=head2 index

The root page (/)

=cut

sub index :Path :Args() {
    my ( $self, $c, @args) = @_;
    
    if ( $c->session->{'loggedIn'} ) {
        $c->stash( 'loggedIn' => 1 );
    }
    else {
        $c->stash( 'loggedIn' => 0 );
    }
}

sub target :Local :Args(1) {
	my ( $self, $c, $target) = @_;
	
	my $targetCats = $c->model('Postgres')->getTargetCats($target);
	
	$c->stash( 'debug' => Dumper($targetCats),
	           'target' => $target,
	           'cats'   => $targetCats,
 	         );	
}

sub category :Path('target') :Args(2) {
	my ( $self, $c, $target, $category) = @_;

	my $targetDevs = $c->model('Postgres')->getTargetDevs($c, $target, $category);
	
	unless ($targetDevs) {
		print "No devices, switching to Graphs\n";
		$c->detach('graph')->($target, $category);
	}
	
	$c->stash( 'debug'    => Dumper($targetDevs),
	           'target'   => $target,
	           'cat'      => $category,
	           'devs'     => $targetDevs,
	           'template' => 'devices.tt',
 	         );	
}

sub graph :Path('target') :Args(3) {
	my ( $self, $c, $target, $cat, $dev) = @_;
	
	my $graphs = $c->model('RRDTool')->graph($target, $cat, $dev);
	
	$c->stash( 'debug'    => Dumper($graphs),
	           'template' => 'graph.tt',
	           'target'   => $target,
	           'cat'      => $cat,
	           'dev'      => $dev,
	           'graphs'   => $graphs,
 	         );	
}

sub graphedit :Local :Args(1) {
	my ( $self, $c, $graph) = @_;
	
	unless ( $c->session->{'graphs'}->{$graph} ) {
		$c->detach('graph');
	}
	
	my $periodString = 'from=-1hours';#default to last hour
	
	my $template = $c->session->{'graphs'}->{$graph};
	
	
	#form defaults
		
	#finish time
    my ($sec, $fmin, $fhour, $fday, $fmonth, $fyear) = localtime(time);
    $fmonth ++;
    $fyear += 1900; 
	
	#start time (finish time minus a day)
	my $smin   = $fmin;
	my $shour  = $fhour;
    my $sday   = $fday - 1;
	my $smonth = $fmonth;
	my $syear  = $fyear;
	
	if ($sday == 0) {
		$smonth --;
		$sday = 1;
		if ($smonth == 0) {
			 $syear --;
			 $smonth = 1;
		}
	}
	
	my %formvals = ( 'rangetype' => 'last',
	                 'number'    => 1,
	                 'units'     => 'hours',
	                 'smin'      => $smin,
	                 'shour'     => $shour, 
	                 'sday'      => $sday, 
	                 'smonth'    => $smonth, 
	                 'syear'     => $syear,
	                 'fmin'      => $fmin,
	                 'fhour'     => $fhour, 
	                 'fday'      => $fday, 
	                 'fmonth'    => $fmonth, 
	                 'fyear'     => $fyear,
    );
	
	
	if ( $c->req->params->{'rangetype'} ) {
	
		if ( $c->req->params->{'rangetype'} eq 'last' ){
			my $num  = $c->req->params->{'number'};
			my $unit = $c->req->params->{'unit'};
			
			$periodString = "from=-$num$unit";
		}
		elsif ( $c->req->params->{'rangetype'} eq 'range' ){
			my $sday   = sprintf("%02d", $c->req->params->{'sday'});
			my $smonth = sprintf("%02d", $c->req->params->{'smonth'});
			my $syear  = $c->req->params->{'syear'};
			my $shour  = sprintf("%02d", $c->req->params->{'shour'});
			my $smin   = sprintf("%02d", $c->req->params->{'smin'});

			my $fday   = sprintf("%02d", $c->req->params->{'fday'});
			my $fmonth = sprintf("%02d", $c->req->params->{'fmonth'});
			my $fyear  = $c->req->params->{'fyear'};
			my $fhour  = sprintf("%02d", $c->req->params->{'fhour'});
			my $fmin   = sprintf("%02d", $c->req->params->{'fmin'});
			
			$periodString = 
			  'from='.$shour.'%3A'.$smin.'_'.$syear.$smonth.$sday.
			  '&until='.$fhour.'%3A'.$fmin.'_'.$fyear.$fmonth.$fday;
		}
	
    }
	
	my $target       = $c->session->{'graphvars'}->{'target'}; 
	my $targetPrefix = $c->session->{'graphvars'}->{'graphitetreeloc'};
	my $dev          = $c->session->{'graphvars'}->{'dev'};
	my $cat          = $c->session->{'graphvars'}->{'cat'};
	
	
	my $clensedTarget = $target;
    $clensedTarget =~ s/\./_/g;

	my $fullTarget = "$targetPrefix.$clensedTarget";
	
	$template =~ s/%HOSTNAME%/$fullTarget/g;
	$template =~ s/%DEVICE%/$dev/g;
	$template =~ s/%PERIOD%/$periodString/g;
	$template =~ s/width=\d+/width=850/;
	$template =~ s/height=\d+/height=500/;
    $template =~ s/%GRAPHITEHOST%/chrisp01.dev/;
	
	$c->stash( 
	           'target'   => $target,
	           'cat'      => $cat,
	           'dev'      => $dev,
	           'graph'    => $template,
	           'index'    => $graph,
	           'formvals' => \%formvals,
 	         );	

    $c->stash('debug' => Dumper($c->stash), );
}

sub begin :Private {
    my ( $self, $c ) = @_;

    $c->session->{'startTime'} = time;
}

=head2 default

Standard 404 error page

=cut

sub default :Private {
    my ( $self, $c ) = @_;
    $c->response->body( 'Page not found' );
    $c->response->status(404);
}

=head2 end

Attempt to render a view, if needed.

=cut

sub end : ActionClass('RenderView') {}

=head1 AUTHOR

Chris Portman

=head1 LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

__PACKAGE__->meta->make_immutable;

1;
