package Grasshopper::Model::Postgres;

use strict;
use warnings;
use parent 'Catalyst::Model::DBI';

use Data::Dumper;

my $DBHOST = $Grasshopper::GHCONFIG->{'DB_HOSTNAME'};
my $DBNAME = $Grasshopper::GHCONFIG->{'DB_DBNAME'};
my $DBUSER = $Grasshopper::GHCONFIG->{'DB_USERNAME'};
my $DBPASS = $Grasshopper::GHCONFIG->{'DB_PASSWORD'};

__PACKAGE__->config(
    dsn           => "DBI:Pg:dbname=$DBNAME;host=$DBHOST",
    user          => $DBUSER,
    password      => $DBPASS,
    options       => {},
);

sub getTargetTree {
	my $self = shift;
    my $dbh  = $self->dbh;
    
    my $targetGroupQuery = q( select target, groupname from targets 
                              order by target -- );
    my $groupHierachyQuery = q( select * from groupings
                                order by groupname -- );
    
    my $targetGroupSth = $dbh->prepare($targetGroupQuery);
    my $groupHierachySth = $dbh->prepare($groupHierachyQuery);
    
    my $targetGroupRes   = $targetGroupSth->execute();
    my $groupHierachyRes = $groupHierachySth->execute();
    
    my %hierachy;
    my %memberships;
    my @tree;
    
    # associate targets with their branch name
    for my $row ( @{$targetGroupSth->fetchall_arrayref( {} ) } ) {
        my $target = $row->{'target'};
        my $group  = $row->{'groupname'};
        
        unless ( $memberships{$group} ) {
			$memberships{$group} = [];
	    }
	    
	    push @{ $memberships{$group} }, { 'text' => $target, 'leaf' => 'true' };
	}

    my @rows = @{$groupHierachySth->fetchall_arrayref( {} ) };

    # Create each branch individually and attach leafs where applicable
    for my $row ( @rows ) {
        my $group    = $row->{'groupname'};
        my $memberof = $row->{'memberof'};

        if ( $memberships{$group} ) {
			push @{$hierachy{$group}}, @{ $memberships{$group} };
		}
	}
    
    # Attach each branch to its parent by placing a reference to the branch
    # on the parent.
    for my $row ( @rows ) {
        my $group    = $row->{'groupname'};
        my $memberof = $row->{'memberof'};

        if ( $memberof ) {
			push @{$hierachy{$memberof}}, { 'text' => $group, 'children' => $hierachy{$group} };
		}    
	}
	
	# Delete any branch that is that doesnt start at the root.
	for my $row ( @rows ) {
        my $group    = $row->{'groupname'};
        my $memberof = $row->{'memberof'};

        if ( $memberof ) {
			delete $hierachy{$group};
		}		
	}
	
	for my $key ( keys %hierachy ) {
		#$hierachy{$key}->{'text'} = $key;
		push @tree, { 'text'     => $key,
		              'children' => $hierachy{$key},
		            };
	}
    
    return wantarray ? @tree : \@tree;
}

sub getTargetCats {
	my $self = shift;
	my $target = shift;
	
	$target or return;
	
    my $dbh  = $self->dbh;
    
	my $catsQuery = q(select category from targetmetrics 
					  where target = ? and category is not NULL
					  group by category
					  order by category --
                     );
                     
    my $sth = $dbh->prepare($catsQuery);
    my $res = $sth->execute($target);
    
    my @categories;
    
    for my $row ( @{$sth->fetchall_arrayref( {} ) } ) {
        push @categories, { 'title' => $row->{'category'} };
	}
	
	print Dumper(\@categories);
	
	return wantarray ? @categories : \@categories;
	
}

sub getTargetDevs {
	my $self     = shift;
	my $c        = shift;
	my $target   = shift;
	my $category = shift;
	
	($target and $category) or return;
	
    my $dbh  = $self->dbh;
    
	my $devsQuery = q(select a.device, b.graphitetreeloc from targetmetrics a
						join targets b on a.target = b.target 
						where a.target = ? and category = ?
						group by a.device, b.graphitetreeloc 
						order by a.device --
                     );
                     
    my $sth = $dbh->prepare($devsQuery);
    my $res = $sth->execute($target, $category);
    
    my @devices;
        
    for my $row ( @{$sth->fetchall_arrayref( {} ) } ) {
        #~ my $linkFriendlyName = $row->{'device'};
        #~ $linkFriendlyName =~ s|/|_|g;
        #~ $devices{ $row->{'device'} } = $linkFriendlyName;
        
        push @devices, { 'title' => $row->{'device'} };
	}
	
	#~ $c->session->{'graphvars'} = { 'graphitetreeloc' => $treeLoc };
	
	@devices or return;
	
	return wantarray ? @devices : \@devices;
	
}

sub getGraphDefs {
	my $self   = shift;
	my $target = shift;
	my $cat    = shift;
	my $dev    = shift;
	
	my $dbh  = $self->dbh;
	
	my $graphQuery = q(select a.graphtempl from graphdefs a
						join targetmetrics b on a.graphname = b.graphdef
						where b.target = ? and b.device = ?
						group by a.graphtempl --
                      );
                      
    my $device = $dev ? $dev : $cat;
    $device =~ s|_|/|g;
    
    my $sth = $dbh->prepare($graphQuery);
    my $res = $sth->execute($target, $device);
               
    my @defs;	
                       
    for my $row ( @{$sth->fetchall_arrayref( {} ) } ) {
		push @defs, $row->{'graphtempl'};
	}

	return wantarray ? @defs : \@defs;
	
}

sub getMetricGrp {
	my $self   = shift || return;
	my $target = shift || return;
	my $dev    = shift || return;
	my $metric = shift || return;
	
	$dev =~ s|_|/|g;
	
	my $dbh = $self->dbh;
	
	my $groupQuery = q(select graphgroup from targetmetrics 
		   			   where target = ?
					   and device   = ?
					   and metric   = ?
					   limit 1  --
                      );
                      
    my $sth = $dbh->prepare($groupQuery);
    my $res = $sth->execute($target, $dev, $metric);
	
	my @groups;
    for my $row ( @{$sth->fetchall_arrayref( {} ) } ) {
		push @groups, $row->{'graphgroup'};
	}
	
	return $groups[0];
}

=head1 NAME

Grasshopper::Model::Postgres - DBI Model Class

=head1 SYNOPSIS

See L<Grasshopper>

=head1 DESCRIPTION

DBI Model Class.

=head1 AUTHOR

Chris Portman

=head1 LICENSE

This library is free software, you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
