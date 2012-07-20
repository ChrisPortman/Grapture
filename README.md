Grasshopper
===========

A horizontally scalable performance monitoring system


Required Packages (Debian)
==========================

 - libcatalyst-perl
 - libcatalyst-action-rest-perl
 - libcatalyst-view-tt-perl
 - libsnmp-perl
 - libnet-snmp-perl
 - rrdtool
 - librrdtool-oo-perl
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

 1. Install the required packages and perl modules.
 
 2. Initialise the database by running the sql script in 
    PostgreSQL.schema which will by default:
     - Create a user 'grasshopper' with password 'hoppergrass'.
     - Create the tables in the public schema and have them owned by
       grasshopper.
       
 3. Edit <git repository>/etc/grasshopper.tmpl adding the appropriate
    details and save as <git repository>/etc/grasshopper.cfg
    
 4. Edit <git repository>/etc/job-distribution.templ adding the
    appropriate details and save as 
    <git repository>/etc/job-distribution.cfg

 5. Add devices to be monitored using the following SQL:
    INSERT INTO targets (target, snmpcommunity, snmpversion)
    VALUES
    ('<hostname>', '<snmpcommunity', <snmpversion>)

 6. Start beanstalkd with a larger than default max msg size.
    # beanstalkd -z 5000000 [&]

 7. Start a worker:
    # cd <git repository>/bin/
    # perl PollerWorker.pl -c ../etc/job-distribution.cfg -d

 8. Start the Poller Master:
    # cd <git repository>/bin/
    # perl PollerMaster.pl -s localhost -p 11300 -i fifo -v

 9. Run a discovery job through the system:
    # cd <git repository>/bin/
    # perl Discovery.pl

10. Start the polling scheduler that will load the poller master with
    jobs every 45secs
    # cd <git repository>/bin/
    # perl Input.pl

11. Start the front end development server
    # cd <git repository>/frontend/Grasshopper/
    # script/grasshopper_server.pl
    
12. Load the web interface:
    http://localhost:3000/js
    

TODO
====

 - Create a config file to store environment setup config
   -> Various paths (eg path to RRD root)
 - Sanity check paths where ever they are used to ensure that the
   inclusion/exclusion of a trailing '/' is handled.
 - Find a better way of managing '/' is device names eg /home,
   GigabitEthernet0/0.  Atm, Im just subbing the / for _ before putting 
   it in a URL and then subbing it back server side.  It will just be a
   matter of time before a device really has a _ in it.
 - Build some server side logic that analyses what a graph make-up is
   and send down graph options the determine the look of the graph.
 - Index the graph groups so that the order in which they appear can be
   specified.  It appears JS will sort therefore, InterfaceErrors
   appears above InterfaceTraffic which is what everyone wants to see.
 - Implement a select box to allow selecting the RRD archive to look at.
   By default it loads the one with the highest resolution, but the
   least history.

 - (FIXED) At the moment, multiple graphs (eg InterfaceTraffic and
   InterfaceErrors) breaks the graph rendering.
