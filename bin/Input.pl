#!/usr/bin/env perl
#$Id: testInput.pl,v 1.9 2012/06/07 03:43:34 cportman Exp $

use strict;
use JSON::XS;
use Data::Dumper;
use DBI;

my $fifo = '/tmp/pollermaster.cmd';

my $dbh = DBI->connect("DBI:Pg:dbname=grasshopper;host=127.0.0.1",
	                       "grasshopper",
	                       "hoppergrass",
	                       #{'RaiseError' => 1},
	                      );
	
if ( not $dbh ) { return; };

my $getSchedQuery = 'select 
                     a.target,  a.device,      a.metric, a.valbase,
	                 a.mapbase, a.counterbits, a.max,    a.category,
	                 a.module, a.output, a.valtype, b.snmpcommunity,
	                 b.snmpversion
                     from targetmetrics a 
                     join targets b on a.target = b.target
                     order by a.target, a.metric --';
                     
my $sth = $dbh->prepare($getSchedQuery);

my $run = 1;
while ($run) {
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
	}

    #~ my $command = 
	#~ "echo '$encodedJobs' | perl PollerMaster.pl -s localhost -p 11300 -i stdin -v";
	#~ print "$command\n";
	#~ my @results = `$command`;
	
	sleep 45;
}




1;

