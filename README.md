Grapture
===========

A horizontally scalable performance monitoring system


Required Packages (Debian)
==========================

 - libcatalyst-perl
 - libcatalyst-modules-perl
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
 - librrds-perl
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
system working in a way that will be suitable for development.  The idea of
running it in production yet is one of pure fantasy, however 
that idea will become a reality in the near future (sooner with your help!).

 1. Install the required packages and perl modules.
 
 2. Initialise the database by running the sql script in 
    sql/grapture.sql which will by default:
     - Create a user 'grapture' with password 'password'.
     - Create the tables in the public schema and have them owned by
       grapture.
       
 3. Edit &lt;git repository&gt;/etc/grapture.tmpl adding the appropriate
    details and save as &lt;git repository&gt;/etc/grapture.cfg
    
 4. Start RRDCached as so:
```
    rrdcached -b /path/to/RRDFiles -F -w 600 -z 300 -l 127.0.0.1 -l $HOSTNAME
```
    
 5. Start beanstalkd with a larger than default max msg size.
```
    beanstalkd -z 5000000 [&]
```

 6. Start the Poller Master:
```
    cd <git repository>/bin
    perl JobDistribtion.pl -c <git_repo>/etc/grapture.cfg -d
```

 7. Start a worker:
```
    cd <git repository>/bin
    perl JobProcessor.pl -c <git_repo>/etc/grapture.cfg -d
```

 8. Start the polling scheduler that will load the Job Distributor with
    jobs every 45secs
```
    cd <git repository>/bin
    perl Input.pl -c <git_repo>/etc/grapture.cfg -d -i 45
```

 9. Start the front end development server
```
    cd <git repository>/frontend/Grapture
    script/grapture_server.pl
```
    
10. Load the web interface:
    http://localhost:3000/

11. Log in (Login button bottom left) using admin:password.
 
12. Add hosts to be monitored using the + button on the 'Targets' title bar.  In the dialogue that appears you can
     add single hosts, many hosts as well as groups to the tree.
     
13. Run a discovery job through the system:
```
    cd <git repository>/bin
    perl Discovery.pl
```

    
UPDATES
=======

17/9/12:
The Web interface now includes dialogues to do much of what had to be
done manually in the database with SQL statements and whatnot.  This
includes adding targets and groups as well as editing existing targets.
More to come.

PREVIOUS:
Processes can now be daemonized on the cli:
```
perl Input.pl -c <full path to cfg> -i 45 -d
perl PollerMaster2.pl -c <full path to cfg> -d
perl PollerWorker.pl -c <full path to cfg> -d
```

RRD Cached is now also be used do reduce the IO writes:
Set at least the RRD_BIND_ADDR option in the config file and start
rrdcached with: 
sudo rrdcached -b DIR_RRD -F -w 600 -z 300 -l 127.0.0.1

There are also some init scripts under etc/init/ note however they
currently contain hardcoded paths applicable to my dev environment. You
will have to update the paths for the DAEMON and DAEMON_OPTS variables.

TODO
====
 - Separate some of the process logic such as discovery and SNMP
   fetching out into some sort of shared processes module.  This will
   potentially allow other components to use it.  Then in the actual 
   pluggins, use small wrappers to 'use' the shared processes as modules.
 - Need to develop more distribution agnostic init scripts.
 - More GUI dialogues to manipulate the way graphs are represented,
   editing metrics and any other tasks that send me back to the database.
 - Implement PostgreSQL stored procedures for adding new targets and
   metrics and eliminate the use of update|insert statements. 
 - Index the graph groups so that the order in which they appear can be
   specified.  It appears JS will sort therefore, InterfaceErrors
   appears above InterfaceTraffic which is what everyone wants to see.

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
