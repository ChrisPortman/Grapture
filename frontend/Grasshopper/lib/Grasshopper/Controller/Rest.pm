package Grasshopper::Controller::Rest;
use Moose;
use namespace::autoclean;

use Data::Dumper;
use RRDTool::OO;

BEGIN {extends 'Catalyst::Controller::REST'; }

__PACKAGE__->config( 'map'     => {'text/html' => 'JSON'} );
__PACKAGE__->config( 'default' => 'application/json'      );

my $RRDFILELOC = $Grasshopper::GHCONFIG->{'DIR_RRD'};
my $RRDHTMLLOC = '/static/rrddata/';

$RRDFILELOC =~ s|([^/])$|$1/|;
$RRDHTMLLOC =~ s|([^/])$|$1/|;

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
	
	my $dir = $RRDFILELOC . $target .'/'.$cat.'/'.$dev;
	
	unless ( -d $dir ) {
		$self->status_no_content($c);
		return 1;
	}

	opendir (my $dh, $dir)
	  or $self->status_no_content($c) and return 1;

    my @rrdFiles = map { $dir.'/'.$_ } #Prepend the full path.
                   grep { m/\.rrd$/ }  #keep the *.rrd files.
                   readdir($dh);

    closedir $dh;
    
    #get the info for each file.
    my @graphs;
    for my $rrd (@rrdFiles) {
		next unless -f $rrd;
		
		my $rrdObj = RRDTool::OO->new( 'file'        => $rrd,
		                               'raise_error' => 0 
		                             )
		  or next;
		
		my $info = $rrdObj->info();
		
		#swap the full path of filename with the HTML loction
		$info->{'filename'} =~ s/$RRDFILELOC/$RRDHTMLLOC/e;
		
		#the ds key in info holds a ref to a hash keyed on the store
		#name.  this needs to be translated to an array of hash refs
		#So, take the store name, add it to a 'name' key inside the stores
		#hash and add each store to an array then make the array the value
		#of 'ds'.
		my %dataStores = %{$info->{'ds'}};
		
		for my $ds ( keys %dataStores ) {
			$dataStores{$ds}->{'name'}  = $ds;
			$info->{'group'} = 
			  $c->model('Postgres')->getMetricGrp($target, $dev, $ds)
			  || undef;
						
			unless ( ref($info->{'ds'}) and ref($info->{'ds'}) eq 'ARRAY') {
				$info->{'ds'} = [];
			}
			
			push @{$info->{'ds'}}, $dataStores{$ds};
		}
		
        push @graphs, $info;
	}

#	print Dumper(\@graphs);
	
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
	
	my $dir = $RRDFILELOC . $target .'/'.$cat.'/'.$dev;
	
	unless ( -d $dir ) {
		print "no directory $dir\n";
		$self->status_no_content($c);
		return 1;
	}

	opendir (my $dh, $dir)
	  or $self->status_no_content($c) and return 1;

    my @rrdFiles = map { $dir.'/'.$_ } #Prepend the full path.
                   grep { m/\.rrd$/ }  #keep the *.rrd files.
                   readdir($dh);

    closedir $dh;
    
    my %objsByGroups;

	my $time = time();
    
    for my $rrd (@rrdFiles) {
		# Go through each RRD file and work out what data sources they 
		# have and what groups the data sources belong to.
	    
		next unless -f $rrd;
		my $rrdObj = RRDTool::OO->new( 'file'        => $rrd,
		                               'raise_error' => 0 
		) or next;
		
		my @dataSources = keys $rrdObj->info()->{'ds'};
		
		for my $ds ( @dataSources ) {
			my $group = $c->model('Postgres')->getMetricGrp($target, $dev, $ds)
			            || $ds;

			unless ( $objsByGroups{$group} ) {
				$objsByGroups{$group} = {};
			}
			
			$objsByGroups{$group}->{$ds} = $rrdObj;
		}
	}
	
	GROUPS:
	for my $group ( keys %objsByGroups ) {
		
		DATAS:
		for my $ds ( keys %{$objsByGroups{$group}} ) {
		
			my $obj  = $objsByGroups{$group}->{$ds};
			my $info = $obj->info();
            my $step = $info->{'step'};
            
            delete $objsByGroups{$group}->{$ds};
            		
			#process each RRA (archive) in the object.
			RRA:
			for my $rra ( @{$info->{'rra'}} ) {
				my $rows      = $rra->{'rows'};
				my $pdpPerRow = $rra->{'pdp_per_row'};

	            my $earliestData = $time - ($step * $pdpPerRow * $rows);
	            my $periodName = 'Since '.gmtime($earliestData);
	            print "Calculating earliest time with $time - ($step * $pdpPerRow * $rows) = $earliestData\n";
	            
	            unless ( $objsByGroups{$group}->{$earliestData} ) {
		            $objsByGroups{$group}->{$earliestData} = [];
				}

				my @plots;
				$obj->fetch_start( 'start' => $earliestData, );
				while ( my ($time, $value) = $obj->fetch_next() ) {
					push @plots, [ $time * 1000, $value ];
				}

				push @{$objsByGroups{$group}->{$earliestData}},
				  { 'label' => $ds, 'plots' => \@plots };
			}
			
		}
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

=head1 AUTHOR

Chris Portman

=head1 LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

__PACKAGE__->meta->make_immutable;

1;
