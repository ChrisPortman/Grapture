Grapture
===========

A horizontally scalable performance monitoring system


Required Packages (Debian)
==========================

 - libcatalyst-perl
 - libcatalyst-action-rest-perl
 - libcatalyst-view-tt-perl
 - libsnmp-perl
 - libnet-snmp-perl
 - liblog-any-adapter-dispatch-perl
 - liblog-dispatch-config-perl
 - libconfig-auto-perl
 - libfile-pid-perl
 - rrdtool
 - rrdcached
 - beanstalkd
 - postgresql
 - pgadmin3 (recommended)
 - libdbd-pg-perl


Additional Perl Modules
=======================

The following perl modules are required although there appears to be no
packages for them at the time of writing:

 - Beanstalk::Client (Author: Graham Barr) 
   (http://search.cpan.org/dist/Beanstalk-Client/lib/Beanstalk/Client.pm)
   

Setup
=====

The following steps should get you to a point where you will have the 
system working in a way that will be good for development.  The idea of
running it in production yet is one of pure fantasy however hopefully
that idea will join us in reallity the near to mid term future.

 1. Install the required packages and perl modules.
 
 2. Initialise the database by running the sql script in 
    PostgreSQL.schema which will by default:
     - Create a user 'grapture' with password 'hoppergrass'.
     - Create the tables in the public schema and have them owned by
       grapture.
       
 3. Edit <git repository>/etc/grapture.tmpl adding the appropriate
    details and save as <git repository>/etc/grapture.cfg
    
 4. Edit <git repository>/etc/job-distribution.templ adding the
    appropriate details and save as 
    <git repository>/etc/job-distribution.cfg

 5. Add devices to be monitored using the following SQL:
```
    INSERT INTO targets (target, snmpcommunity, snmpversion)
    VALUES
    ('<hostname>', '<snmpcommunity', <snmpversion>)
```

 6. Start beanstalkd with a larger than default max msg size.
```
    beanstalkd -z 5000000 [&]
```

 7. Start a worker:
```
    cd <git repository>/bin
    perl PollerWorker.pl -c ../etc/job-distribution.cfg -d
```

 8. Start the Poller Master:
```
    cd <git repository>/bin
    perl PollerMaster.pl -s localhost -p 11300 -i fifo -v
```

 9. Run a discovery job through the system:
```
    cd <git repository>/bin
    perl Discovery.pl
```

 10. Start the polling scheduler that will load the poller master with
    jobs every 45secs
```
    cd <git repository>/bin
    perl Input.pl
```

 11. Start the front end development server
```
    cd <git repository>/frontend/Grapture
    script/grapture_server.pl
```
    
 12. Load the web interface:
    http://localhost:3000/js
    
UPDATES
=======

Processes can now be daemonized on the cli:
perl Input.pl -c <full path to cfg> -i 45 -d
perl PollerMaster2.pl -c <full path to cfg> -d
perl PollerWorker.pl -c <full path to cfg> -d

RRD Cached can now also be used do reduce the IO writes:
Set at least the RRD_BIND_ADDR option in the config file and start
rrdcached with: 
sudo rrdcached -b DIR_RRD -F -w 600 -z 300 -l 127.0.0.1

There are also some init scripts under etc/init/ note however they
currently contain hardcoded paths applicable to my dev environment. You
will have to update the paths for the DAEMON and DAEMON_OPTS variables.

TODO
====

 - Index the graph groups so that the order in which they appear can be
   specified.  It appears JS will sort therefore, InterfaceErrors
   appears above InterfaceTraffic which is what everyone wants to see.
 - Some operational tasks such as adding new hosts for monitoring and
   re-discovering hosts require manual and direct manipulation of the
   database.  While it is expected that these tasks should be automated,
   the GUI should include the ability to add new hosts and tigger a 
   re-discovery in addition, automated processes should be facilitated 
   by an API rather than having external processes send directly to the
   DB.


 - (FIXED)Add more flexible device filtering so that for example, 
   interfaces that are down wont be polled. 
     - Metric discovery modules now have to option of including a filter
       sub routine that can contain logic of arbitrary complexity that
       will determine if a component should be enabled for monitoring.
 - (FIXED)Build some server side logic that analyses what a graph make 
   up is and send down graph options the determine the look of the graph.
 - (FIXED) Find a better way of managing '/' is device names eg /home,
   GigabitEthernet0/0.  Atm, Im just subbing the / for _ before putting 
   it in a URL and then subbing it back server side.  It will just be a
   matter of time before a device really has a _ in it.
     - Replaced the substitution of / with _ with _SLSH_ which is much
       more deliberate and not likely to appear naturally in any device
       or metric name.
 - (FIXED) The Poller Master currently takes in a batch of jobs, waits
   for them to finish and then takes another batch.  Potentially this 
   will mean that a single dud job could halt the whole system.  The 
   master should accept jobs constantly, put them into beanstalk and 
   track until a result code comes back.  The master should also force 
   an optional timeout on jobs so that they will only sit in the queue 
   for a maximum specified time.  This will solve the possible situation 
   whereby if no pollers are running, jobs that are time relative (eg 
   polling tasks) dont just sit and queue up and then all running as 
   fast as possible as soon as a worker comes online when they are no 
   longer relevant anyway.
   (UPDATE: This is being addressed in PollerMaster2.pl which is working
   but hasnt had a chance to soak)
 - (FIXED) At the moment, multiple graphs (eg InterfaceTraffic and
   InterfaceErrors) breaks the graph rendering.
 - (FIXED) Create a config file to store environment setup config
   -> Various paths (eg path to RRD root)
 - (FIXED) Sanity check paths where ever they are used to ensure that the
   inclusion/exclusion of a trailing '/' is handled.
 - (FIXED) Add a reset graph button to refresh a graph to its full range.
 - (FIXED) Implement a select box to allow selecting the RRD archive to look at.
   By default it loads the one with the highest resolution, but the
   least history.
