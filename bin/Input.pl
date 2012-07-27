#!/usr/bin/env perl
#$Id: testInput.pl,v 1.9 2012/06/07 03:43:34 cportman Exp $

use strict;
use Config::Auto;
use JSON::XS;
use DBI;

my $fifo = '/tmp/pollermaster.cmd'; # FIXME, this should probably be in the config file
my $dbh;
my $sth;
my $config;

my $getSchedQuery = q/select 
                     a.target,  a.device,      a.metric, a.valbase,
	                 a.mapbase, a.counterbits, a.max,    a.category,
	                 a.module, a.output, a.valtype, b.snmpcommunity,
	                 b.snmpversion
                     from targetmetrics a
                     join targets b on a.target = b.target
                     where a.enabled = true
                     order by a.target, a.metric --/;

sub getConfig {
	my $file = shift;
	return unless ($file and -f $file);
	my $config = Config::Auto::parse($file);
	return $config;
}

sub loadConfig {

    $config = getConfig( '../etc/grasshopper.cfg' ); # FIXME, should be from the cli
    my $DBHOST = $config->{'DB_HOSTNAME'};
    my $DBNAME = $config->{'DB_DBNAME'};
    my $DBUSER = $config->{'DB_USERNAME'};
    my $DBPASS = $config->{'DB_PASSWORD'};

    $dbh->disconnect if $dbh; # disconnect if connected
    $dbh = DBI->connect("DBI:Pg:dbname=$DBNAME;host=$DBHOST", $DBUSER, $DBPASS, 
        #{'RaiseError' => 1},
        )
        or die "Failed to connect to the database: $DBI::errstr\n";

    $sth = $dbh->prepare($getSchedQuery);

    return 1

}
	
                     
my $run = 1;
my $reload = 0;

$SIG{HUP} = { $reload++ };
$SIG{DIE} = { $run = 0 };

while ($run) {

        if ($reload) { loadConfig(); $reload = 0 }

	my $res = $sth->execute();
	
	my %jobs;
	
	for my $job ( @{ $sth->fetchall_arrayref( {} ) } ) {
	    #manual bits for now...    
		my $version   = '2';
		my $community = 'oidR0rk0';
		
		#stuff from the DB
		my $target = $job->{'target'};
		my $metricDetails = {
			'metric'      => $job->{'metric'},
			'device'      => $job->{'device'},
			'valbase'     => $job->{'valbase'},
			'mapbase'     => $job->{'mapbase'},
			'counterbits' => $job->{'counterbits'},
			'category'    => $job->{'category'},
			'max'         => $job->{'max'},
			'valtype'     => $job->{'valtype'},
		};
		
		unless ( $jobs{$target} ) {
		    $jobs{$target} = {
				'module'      => $job->{'module'},
				'output'      => $job->{'output'},
				'waitTime'    => 300,
				'methodInput' => {
					'target'    => $target,
					'version'   => $job->{'snmpversion'},
					'community' => $job->{'snmpcommunity'},
					'metrics'   => [],
				},
			}
		}
		
		push @{$jobs{$target}->{'methodInput'}->{'metrics'}}, $metricDetails;	
	}
	
	my @jobList;
	
	for my $key ( keys %jobs ) {
		push @jobList, $jobs{$key};
	}
	
	my $encodedJobs = encode_json(\@jobList);
	
	if ( -p $fifo ) {
		open (my $fifoFH, '>', $fifo)
	      or die "Could not open FIFO, can't continue.\n";
	    
	    print $fifoFH "$encodedJobs\n";
	    
	    close $fifoFH;
	}
	else {
		print "FIFO not created, is the pollerMaster running?\n";
# FIXME, should now probably exit?
	}

    #~ my $command = 
	#~ "echo '$encodedJobs' | perl PollerMaster.pl -s localhost -p 11300 -i stdin -v";
	#~ print "$command\n";
	#~ my @results = `$command`;

	sleep 45; # FIXME, this should probably be configurable

}

exit;
