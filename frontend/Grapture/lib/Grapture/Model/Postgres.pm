package Grapture::Model::Postgres;

use strict;
use warnings;
use base 'Catalyst::Model::DBI';
use Grapture::Storage::MetaDB;
use Data::Dumper;

my $DBHOST = $Grapture::GHCONFIG->{'DB_HOSTNAME'};
my $DBNAME = $Grapture::GHCONFIG->{'DB_DBNAME'};
my $DBUSER = $Grapture::GHCONFIG->{'DB_USERNAME'};
my $DBPASS = $Grapture::GHCONFIG->{'DB_PASSWORD'};

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
    my $targetsWithAggsQuery = q( select target from targetmetrics 
                                  where aggregate = true
                                  and enabled = true
                                  group by target -- );
    
    my $targetGroupSth     = $dbh->prepare($targetGroupQuery);
    my $groupHierachySth   = $dbh->prepare($groupHierachyQuery);
    my $targetsWithAggsSth = $dbh->prepare($targetsWithAggsQuery);
    
    my $targetGroupRes     = $targetGroupSth->execute();
    my $groupHierachyRes   = $groupHierachySth->execute();
    my $targetsWithAggsRes = $targetsWithAggsSth->execute();
    
    my %hierachy;
    my %memberships;
    my @tree;
    my %targetsWithAggs; #targets with aggregated metrics
    my %groupsWithAggs;  #groups that have the aggregation leaf
    
    #Build the list of targets that have metrics that need to be displayed
    #aggregated with the same metrics of other hosts.  Eg. for a web cluster
    #serving a webpage, it is useful to see the total page serves for the
    #whole cluster holistically
    for my $row ( @{$targetsWithAggsSth->fetchall_arrayref( {} ) } ) {
		$targetsWithAggs{ $row->{'target'} } = 1;
	}
    
    # associate targets with their branch name
    for my $row ( @{$targetGroupSth->fetchall_arrayref( {} ) } ) {
        my $target = $row->{'target'};
        my $group  = $row->{'groupname'};
        
        unless ( $memberships{$group} ) {
			$memberships{$group} = [];
	    }
	    
	    push @{ $memberships{$group} }, { 'text' => $target, 'leaf' => 'true' };
	    
	    #Add an Aggregation leaf if appropriate
	    if ( $targetsWithAggs{ $target } ) {
			unless ( $groupsWithAggs{$group} ) {
				unshift @{ $memberships{$group} }, 
				  { 'text' => $group.'_Aggregates', 'leaf' => 'true' };
				$groupsWithAggs{$group} = 1;
			}
		}
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

        unless ( $hierachy{$group} ) {
			$hierachy{$group} = [];
		}

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
	
	# Push each top level branch into an array
	for my $key ( keys %hierachy ) {
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
    my $sth;
    my $res;
    
	my $catsQuery = q(select category from targetmetrics 
					  where target = ? and category is not NULL
					  group by category
					  order by category --
                     );
                     
    my $aggCatsQuery = q( select a.category from targetmetrics a
  						  join targets b on a.target = b.target
						  where b.groupname = ?
						  and aggregate = true
						  and enabled = true
						  group by a.category
						  order by a.category -- );
						  
    if ( $target =~ /^(.+)_Aggregates/ ) {
		my $group = $1;
	    $sth = $dbh->prepare($aggCatsQuery);
	    $res = $sth->execute($group);
	}						  
    else {                     
	    $sth = $dbh->prepare($catsQuery);
	    $res = $sth->execute($target);
	}
    
    my @categories;
    
    for my $row ( @{$sth->fetchall_arrayref( {} ) } ) {
        push @categories, { 'title' => $row->{'category'} };
	}
	
	return wantarray ? @categories : \@categories;
	
}

sub getTargetConfig {
	my ($self, $c) = @_;
    my $dbh  = $self->dbh;

    my $target = $c->request->params->{'target'} || return;
   
    my $targetConfQuery = q/select * from targets where target = ? --/;
    my $targetConfSth = $dbh->prepare($targetConfQuery);
    $targetConfSth->execute($target);
    
    my ($targetConf) = @{$targetConfSth->fetchall_arrayref( {} ) };
    
    if ($targetConf) {
		return {
			name      => $targetConf->{'target'},
			version   => $targetConf->{'snmpversion'},
			community => $targetConf->{'snmpcommunity'},
			group     => $targetConf->{'groupname'},
		};
	}
	
	return;
}

sub getTargetDevs {
	my $self     = shift;
	my $c        = shift;
	my $target   = shift;
	my $category = shift;
	
	($target and $category) or return;
	
    my $dbh  = $self->dbh;
    my $sth;
    my $res;
    
	my $devsQuery = q(select device from targetmetrics
						where target = ? and category = ?
						and enabled = true
						group by device --
                     );
                     
    my $aggDevsQuery = q(select a.device from targetmetrics a
						 join targets b on a.target = b.target
						 where b.groupname = ?
						 and a.category = ?
						 and a.aggregate = true
						 and a.enabled = true
						 group by a.device -- );                     

    if ( $target =~ /^(.+)_Aggregates/ ) {
		my $group = $1;
	    $sth = $dbh->prepare($aggDevsQuery);
	    $res = $sth->execute($group, $category);
	}
	else {
        $sth = $dbh->prepare($devsQuery);
	    $res = $sth->execute($target, $category);
	}
    
    my @devices;
        
    for my $row ( @{$sth->fetchall_arrayref( {} ) } ) {
        push @devices, { 'title' => $row->{'device'} };
	}

	@devices = sort { sortNatural($a->{'title'}, $b->{'title'}) } @devices;
	
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
    $device =~ s|_SLSH_|/|g;
    
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
	
	$dev =~ s|_SLSH_|/|g;
	
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

sub getDeviceMetrics {
	my $self   = shift || return;
	my $target = shift || return;
	my $dev    = shift || return;
	
	$dev =~ s|_SLSH_|/|g;
	
	my $dbh = $self->dbh;
	
	my $groupQuery = q(select metric, graphgroup, graphorder
	                   from targetmetrics
	                   where target = ? and device = ?
                       order by graphorder --
                      );
                      
    my $sth = $dbh->prepare($groupQuery);
    my $res = $sth->execute($target, $dev);
	
	my @metrics;
    for my $row ( @{$sth->fetchall_arrayref( {} ) } ) {
		push @metrics, $row;
	}
	
	return wantarray ? @metrics : \@metrics;
}

sub getAggMetrics {
	my $self   = shift;
	my $group  = shift;
	my $dev = shift;
	my $dbh = $self->dbh;

	$dev =~ s|_SLSH_|/|g;
	
	my $aggMetricsQuery = q(select a.target, a.metric from targetmetrics a
							join targets b on a.target = b.target
							where a.device = ?
							and b.groupname = ?
							and enabled = true
							and aggregate = true
							order by graphorder -- 
						   );
                      
    my $sth = $dbh->prepare($aggMetricsQuery);
    my $res = $sth->execute($dev, $group);
	
	my @metrics;
    for my $row ( @{$sth->fetchall_arrayref( {} ) } ) {
		push @metrics, $row;
	}
	
	return wantarray ? @metrics : \@metrics;
}

sub getGroupMetrics {
	my $self   = shift || return;
	my $target = shift || return;
	my $group  = shift || return;
	
	my $dbh = $self->dbh;
	
	my $groupQuery = q(select metric, graphorder from targetmetrics
	                   where target = ?
	                   and (graphgroup = ? or metric = ?)
                       group by metric, graphorder
                       order by graphorder --
                      );
                      
    my $sth = $dbh->prepare($groupQuery);
    my $res = $sth->execute($target, $group, $group);

    my @metrics;
    
    for my $row ( @{$sth->fetchall_arrayref( {} ) } ) {
		push @metrics, $row->{'metric'};
	}
	
    return wantarray ? @metrics : \@metrics;
}

sub getTargetsWithMetric {
	my $self        = shift;
	my $targetGroup = shift;
	my $device      = shift;
	my $metric      = shift;
	
	my $dbh = $self->dbh;

    my $query = q( select a.target from targetmetrics a
                   join targets b on a.target = b.target
                   where b.groupname = ?
                   and a.device = ?
                   and a.metric = ?
                   and a.enabled = true
                   and a.aggregate = true -- );	
	
    my $sth = $dbh->prepare($query);
    my $res = $sth->execute($targetGroup, $device, $metric);
    
    my @targets;
    
    for my $row ( @{$sth->fetchall_arrayref( {} ) } ) {
		push @targets, $row->{'target'};
	}
	
    return wantarray ? @targets : \@targets;
}

sub getGraphGroupSettings {
	my $self = shift;
	my $dbh = $self->dbh;
    my %groupSettings;
    	
	my $groupQuery = q(select * from graphgroupsettings);
    my $sth = $dbh->prepare($groupQuery);
    my $res = $sth->execute();

    for my $row ( @{$sth->fetchall_arrayref( {} ) } ) {
		my $group = delete $row->{'graphgroup'};
		$groupSettings{$group} = {};
		
		for my $key ( keys( %{$row} ) ) {
			$groupSettings{$group}->{$key} = $row->{$key};
		}	
    }
    
	return wantarray ? %groupSettings : \%groupSettings;
}

sub getMetricMax {
	my $self   = shift;
    my $target = shift;
    my $device = shift;
    my $metric = shift;
    
    $device =~ s|_SLSH_|/|g;
    my $max;
    
    unless ( $target and $device and $metric ) {
		return;
	} 
    	
	my $dbh = $self->dbh;
	
	my $maxQuery = q/select max from targetmetrics
	                 where target = ?
	                 and device = ?
	                 and metric = ? --/;
    
    my $sth = $dbh->prepare($maxQuery);
    my $res = $sth->execute($target, $device, $metric);
    
    for my $row ( @{$sth->fetchall_arrayref( {} ) } ) {
		$max = $row->{'max'};		
	}
	$max or return;
	return $max;
}

sub addHosts {
	my ($self, $c) = @_;
	my $dbh = $self->dbh;

    #set up some db queries
    my $checkGroupQuery = q/select groupname from groupings
                            where groupname = ? --/;
    my $checkGroupSth   = $dbh->prepare( $checkGroupQuery );
    
    my $checkHostQuery  = q/select target from targets
                            where target = ? --/;
    my $checkHostSth = $dbh->prepare( $checkHostQuery );
    
    my $addHostQuery    = q/insert into targets 
                            (target, snmpversion, snmpcommunity, groupname)
                            values
                            (?, ?, ?, ?) -- /;
    my $addHostSth = $dbh->prepare( $addHostQuery );                           
	
	#process the request
	my @hosts;
	
	if ($c->request->params->{'hostDetails'}) {
		#adding bulk hosts
		for my $host (split /\n/, $c->request->params->{'hostDetails'}){
			my ($hostname, $version, $community, $group)
			  = split /\s?,\s?/, $host;
			
			push @hosts, { hostname  => $hostname,
			               version   => $version,
			               community => $community,
			               group     => $group,
			             };
		}
    }
	else {
		#adding a single host
		my $hostname  = $c->request->params->{'hostname'};
		my $version   = $c->request->params->{'snmpversion'};
		my $community = $c->request->params->{'snmpcommunity'};
		my $group     = $c->request->params->{'targetgroup'};
		
		push @hosts, { hostname  => $hostname,
			           version   => $version,
			           community => $community,
			           group     => $group,
		             };
    }
	
	my @failedHosts;
	my $successCount = 0;
    my $hostname;

	for my $host (@hosts) {	
		$hostname  = $host->{'hostname'};
		my $version   = $host->{'version'};
		my $community = $host->{'community'};
		my $group     = $host->{'group'};
		
		#check that the host doesnt exist
		my $hostResult = $checkHostSth->execute($hostname);
		
		unless ( scalar @{$checkHostSth->fetchall_arrayref( {} ) } ) {
			#check that the group exists
			my $groupResult = $checkGroupSth->execute($group);
			
			if ( scalar @{$checkGroupSth->fetchall_arrayref( {} ) } ) {
				#add the new host
				$addHostSth->execute($hostname, $version, 
				                     $community, $group);
				$successCount ++;
			}
			else {
			    push @failedHosts, { host => $hostname, 
			                         data  => "The group $group does not exist",
			                       };
			}
		}
		else {
		    push @failedHosts, { host => $hostname, 
		                         data  => "Hostname already in system",
		                       };
		}
		
	}

    my $message;
	my $resultBool;	
	if ( scalar @failedHosts ) {
		$message  = "Successfully added $successCount hosts.<br /><br />";
		$message .= "The following hosts failed:<br />";
		for my $failed (@failedHosts) {
			$message .= $failed->{'host'}.' - '.$failed->{'data'}."<br />";
		}
	}
	elsif ( $successCount > 1 ) {
		$message = "Successfully added $successCount hosts.<br />";
		$resultBool = 'true';
	}
	else {
		$message = "Successfully added $hostname<br />";
		$resultBool = 'true';
	}
	
	return ($resultBool, $message);
}

sub editHost {
	my ($self, $c) = @_;
	my $dbh = $self->dbh;

    #set up some db queries
    my $checkGroupQuery = q/select groupname from groupings
                            where groupname = ? --/;
    my $checkGroupSth   = $dbh->prepare( $checkGroupQuery );
    
    my $checkHostQuery  = q/select target from targets
                            where target = ? --/;
    my $checkHostSth = $dbh->prepare( $checkHostQuery );
    
    my $editHostQuery    = q/update targets set 
                            snmpversion = ?,
                            snmpcommunity = ?,
                            groupname = ? 
                            where target = ? --/;
    my $editHostSth = $dbh->prepare( $editHostQuery );

    my $editDiscoverHostQuery = q/update targets set 
                                  snmpversion = ?,
                                  snmpcommunity = ?,
                                  groupname = ?,
                                  lastdiscovered = null
                                  where target = ? --/;
    my $editDiscoverHostSth = $dbh->prepare( $editDiscoverHostQuery );
                              
	
	#process the request
	my $hostname     = $c->request->params->{'hostname'} || return;
	my $version      = $c->request->params->{'snmpversion'} || return;
	my $community    = $c->request->params->{'snmpcommunity'} || return;
	my $group        = $c->request->params->{'group'} || return;
	my $rediscover   = $c->request->params->{'rediscover'} || undef;

    my $message;
	my $resultBool;	
    	
	#check that the group exists
	my $groupResult = $checkGroupSth->execute($group);
	unless ( scalar @{$checkGroupSth->fetchall_arrayref( {} ) } ) {
	    $message = "The group $group does not exist";
	    return (undef, $message);
	}

	#add the new host
	if ($rediscover) {
		print "Enabling $hostname for rediscover\n";
		$editDiscoverHostSth->execute($version, $community, $group, $hostname );
	}
	else {
		print "NOT enabling $hostname for rediscover\n";	
		$editHostSth->execute($version, $community, $group, $hostname );
	}
	$message = "Successfully updated $hostname";			                     
	return (1, $message);
}

sub addGroup {
	my ($self, $c) = @_;
	my $dbh = $self->dbh;
	
	my $groupName   = $c->request->params->{'groupname'};
	my $parentGroup = $c->request->params->{'parentgroup'};
	
	my $resultBool;
	my $message;
	
	$parentGroup = undef if $parentGroup eq 'Targets';

    #set up some db queries
    my $checkGroupQuery = q/select groupname from groupings
                            where groupname = ? --/;
    my $checkGroupSth = $dbh->prepare($checkGroupQuery);
    
    my $createGroupQuery = q/insert into groupings (groupname, memberof)
                             values
                             (?, ?) --/;
    my $createGroupSth = $dbh->prepare($createGroupQuery);
    
    #check if the group already exists:
    $checkGroupSth->execute($groupName);
    if ( scalar @{$checkGroupSth->fetchall_arrayref( {} ) } ) {
		$message = "The group $groupName already exists.";
	}
	else {
		if ( $createGroupSth->execute($groupName, $parentGroup) ) {
			$resultBool ++;
			$message = "Successfully added group $groupName";
		}
		else {
			$message = "An error occured adding group $groupName to the database";
        }
	}
	
	return ($resultBool, $message);
}

sub checkUserLogin {
	my $self     = shift;
    my $username = shift || return;
    my $password = shift || return;

	my $dbh = $self->dbh;
	
	my $query = q( select username from users
	               where username = ?
	               and password = md5(?)
	               limit 1 -- );
	my $sth = $dbh->prepare($query);
	$sth->execute($username, $password);
	
	if ( scalar @{$sth->fetchall_arrayref( {} ) } ) {
		return 1;
	}
	
	return;
}

sub getMetaSysStats {
    my $self = shift;
    my $metaDB = Grapture::Storage::MetaDB->new();

    my %sysStats = (
	    targetCount => $metaDB->getTargetCount(),
	    metricCount => $metaDB->getMetricCount(),
	    notDiscTargetCount => $metaDB->getNotDiscTargetCount(),
	    lastDiscovery => $metaDB->getLastDiscovery(),
    );
    
    return wantarray ? %sysStats : \%sysStats;
}

sub sortNatural {
	my $a = shift;
	my $b = shift;
	my $caseInsen = shift;
	
	if ($caseInsen) {
		$a = lc($a);
		$b = lc($b);
	}
	
	my @aElems = split //, $a;
	my @bElems = split //, $b;

	if ($a eq $b) {
		return 0;
	}
	
	my $length = ($#aElems > $#bElems) ? $#aElems : $#bElems;
	
	for my $i ( 0 .. $length ) {
		#check to see if both have bee the same to this point but one
		#has stopped
		unless (defined $aElems[$i]) {
			return -1;
		}
		unless (defined $bElems[$i]) {
			return 1;
		}

        next if ($aElems[$i] eq $bElems[$i]);
        
        my $aRemainder = join('', @aElems[$i..$#aElems] );
        my $bRemainder = join('', @bElems[$i..$#bElems] );

		if (     $aRemainder =~ /^\d+(?:\.\d+)?$/ 
		     and $bRemainder =~ /^\d+(?:\.\d+)?$/ ) {
				 
		    my $result = $aRemainder <=> $bRemainder;
		    return $result;			 
		}
		else {
		    my $result = $aElems[$i] cmp $bElems[$i];
		    return $result;			 
		}
	}
	die "Couldnt compare\n";
}

=head1 NAME

Grapture::Model::Postgres - DBI Model Class

=head1 SYNOPSIS

See L<Grapture>

=head1 DESCRIPTION

DBI Model Class.

=head1 AUTHOR

Chris Portman

=head1 LICENSE

This library is free software, you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
