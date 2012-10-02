#!/bin/false

package Grapture::Storage::MetaDB;

use strict;
use Data::Dumper;
use DBI;
use Grapture::Common::Config;
use parent qw( Grapture );
use Log::Any qw( $log );

sub new {
    my $class   = shift;
    $class = ref $class || $class;

    my $config = Grapture::Common::Config->new();

    my $dbhost = $config->getSetting('DB_HOSTNAME');
    my $dbname = $config->getSetting('DB_DBNAME');
    my $dbuser = $config->getSetting('DB_USERNAME');
    my $dbpass = $config->getSetting('DB_PASSWORD');


    unless ($dbhost and $dbname and $dbuser and $dbpass ) {
        $log->error('MetaDB object missing db settings');
        return;
    }

    my $dbh = DBI->connect(
        "DBI:Pg:dbname=$dbname;host=$dbhost",
        $dbuser, $dbpass,
        {
            'PrintError' => 0,
        },
    ) || return;
    

    my %selfHash = ( 'dbh' => $dbh );

    my $self = bless( \%selfHash, $class );

    return $self;
}

=head2 runFunction

This method provides a common interface to any Grapture stored functions
and procedures in the database. It does however rely on the stored
function providing much of the error handling and this function being
able to trust that the arguments provided are sane.  

Each function expects a certain number of arguments and will not run
if the number of arguments supplied is not the number expected.  There
fore, any optional arguments should be supplied as NULL.

Following are a list of stored functions and their expected arguments.

head3 add_group

Creates a group that is used in the display tree.

    @args = (
        <group_name>,    # Required, is the name of the new group.
        <parent_group>,  # String. if NULL, new group will be a
                         # new branch off the trunk.
    );

head3 add_or_update_target

Adds a new target or updates an existing target.

    @args = (
        <target>,         # The target to add or update
        <snmp_version>,   # 1|2
        <snmp_community>, # SNMP community string with read permission
        <group_name>,     # Group the target should appear in.  If NULL
                          # it will appear in Unknown.
        <rediscover>,     # Integer or NULL.  If integer > 0, the
                          # lastdiscovered field will be cleared so that
                          # it will be included in the next discovery
                          # process.

head3 add_or_update_target_metric

Adds a new target metric or updates an exisitng one.

    @args = (
        <target>,
        <device>,
        <metric>,
        <mapbase>, 
        <counterbits>,
        <doer module>,
        <output module>,
        <valbase>,
        <max>,
        <category>,
        <valtype>,
        <graphgroup>,
        <enabled>,
        <graphorder>,
        <aggregate>,
    );

head3 target_discovered

Updates the lastdiscovered field on a target.

    @args = (
        <target>,
    );

=cut

sub runFunction {
    my $self     = shift;
    my $function = shift || return;
    my @args     = @_;
    
    #Add any DB stored functions to this hash as they are created.  This
    #hash will be used to validate the value of $function and NULL fill
    #any shortage in @args.
    my %functionRequiredArgs = (
        'add_group'                   => 2,
        'add_or_update_target'        => 5,
        'add_or_update_target_metric' => 15,
        'target_discovered'           => 1,
    );
    
    unless ($functionRequiredArgs{$function}) {
        $log->error("$function is not a valid DB function or the number of args is wrong");
        return;
    }
    unless ( scalar @args == $functionRequiredArgs{$function} ) {
        $log->error("Incorrect number of arguments for function $function.");
        return;
    }        
    
    for my $idx ( 0 .. $#args ) {
        if ( not defined($args[$idx]) or $args[$idx] =~ /^NULL$/i ) {
            $args[$idx] = 'NULL';
        }
        else {
            $args[$idx] = "'$args[$idx]'";
        }
    }
    
    my $dbh   = $self->{'dbh'};
    my $query = 'SELECT '.$function.'('.join(', ', @args).') --';
    
    my $sth = $dbh->prepare($query);
    
    $sth->execute() or return;
    
    return 1;
}

sub getTargetsForDiscovery {
    my $self = shift;
    my $dbh  = $self->{'dbh'};
    my @targets;
        
    my $query = q/SELECT target, snmpversion, snmpcommunity
                  FROM targets
                  WHERE lastdiscovered is NULL --/;
                  
    my $sth = $dbh->prepare($query);
    my $res = $sth->execute() or return;


    for my $target ( @{ $sth->fetchall_arrayref( {} ) } ) {
        push @targets, $target; #push the row hash
    }
    
    return wantarray ? @targets : \@targets;    
}

sub storeDiscovery {
    my $self    = shift;
    my $results = shift;
    
    unless ( ref($results) and ref($results) eq 'ARRAY' ) {
        $log->error(
            'Discovery result needs to be in the form of an ARRAY ref.');
        return;
    }

    my %seenTargets;

    for my $result ( @{$results} ) {

		if ( $result->{'target'} ) {
		    unless ( $seenTargets{ $result->{'target'} }) {

				$self->runFunction('target_discovered', $result->{'target'})
                  or $log->error('Failed to set the discovery time of '.$result->{'target'});

				$seenTargets{ $result->{'target'} } = 1;
			}
		}
        
        $self->runFunction(
            'add_or_update_target_metric', 
            $result->{'target'},      $result->{'device'}, 
            $result->{'metric'},      $result->{'mapbase'}, 
            $result->{'counterbits'}, 'FetchSnmp', 
            'RRDTool',                $result->{'valbase'}, 
            $result->{'max'},         $result->{'category'}, 
            $result->{'valtype'},     $result->{'graphgroup'}, 
            $result->{'enabled'},     $result->{'graphorder'}, 
            $result->{'aggregate'},
        ) or $log->error('Could not add or update a metric');
	}

    return 1;
}

sub getMetricPolls {
    my $self    = shift;
    my $dbh   = $self->{'dbh'};
    my @polls;
    
    my $query = q/SELECT 
                  a.target,  a.device,      a.metric, a.valbase,
	              a.mapbase, a.counterbits, a.max,    a.category,
	              a.module, a.output, a.valtype, b.snmpcommunity,
	              b.snmpversion
                  FROM targetmetrics a
                  JOIN targets b on a.target = b.target
                  WHERE a.enabled = true
                  ORDER by a.target, a.metric --/;

    my $sth = $dbh->prepare($query);
    my $res = $sth->execute() or return;

    return wantarray ? @{ $sth->fetchall_arrayref( {} ) } 
                     : $sth->fetchall_arrayref( {} );    
}


1;        
