#!/usr/bin/env perl
#$Id: Munge.pm,v 1.5 2012/06/07 03:43:34 cportman Exp $

=head1 GH::Jobsdoer::Munge

=head2 Description

  The Munge module provides various methods that perform manipulations
  and calculations on FetchSnmp results.

  It uses memcached to store values between iterations where required
  enabling subsequent iterations to run on different worker hosts and
  still have access to the data.

=head2 Methods

=cut

package GH::Jobsdoer::Munge;

use strict;
use warnings;

use Cache::Memcached;
use Data::Dumper;
use Math::BigInt;
use Math::BigFloat;

sub new {
    my $class = shift;
    $class = ref($class) if ref($class);    #in case we're cloning the obj.

    my $data = shift;

    unless ( ref($data) and ref($data) eq 'HASH' ) {
        return;
    }

    my %selfhash;
    $selfhash{'data'} = $data;
    $selfhash{'cacheObj'} =
      Cache::Memcached->new( { 'servers' => ['chrisp01.dev:11211'] } );

    my $self = bless( \%selfhash, $class );

    #print Dumper($self);

    return $self;
}

=head3 perSecond()

  The perSecond method compares the current result with the previous one
  as well as the timestamps to determine the average rate per second
  for the time period.

  perSecond = <result> - <prev._result> / seconds_elapsed

  The method also considers counter roll (where the counter reaches its
  maximum value and restarts from zero) by checking to see if the new
  result is less than the previous result. If so, the counters max value
  (2 ** counter_bits) is added to the new result to reveal the true
  value for the purposes of the above calculation.

  perSecond = (<result> + <counter_max>) - <prev._result> / secs_elapsed

  Note that it is still
  the raw result that is stored in memcached for use in the next iteration.

  TODO: Counters will also reset to zero on a reboot.  Need to also get
  and compare system uptime to dectect this scenario, and manage it
  appropriately.

=cut

sub perSecond {

    my $self   = shift;
    my $result = $self->{'data'};
    my $mungedResult;

    #pull some vars for convieniance
    my $value       = $result->{'value'};
    my $adjustedVal = $value;
    my $timestamp   = $result->{'timestamp'};
    my $target      = $result->{'target'};
    my $device      = $result->{'device'};
    my $metric      = $result->{'metric'};
    my $counterbits = $result->{'counterbits'};

    #Build a fully qualified metric name for memcached storage.
    my $metricName = $target . '.' . $device . '.' . $metric;
    $metricName =~ s/\s/_/g;    #remove any spaces

    #get the value from the previous run
    my $prevValHash = $self->_getCache($metricName);

    if ($prevValHash) {

        #Create Bigint Objects
        my $bigCounterMax = Math::BigFloat->bpow( 2, $counterbits );
        my $bigPrevVal    = Math::BigFloat->new( $prevValHash->{'value'} );
        my $bigAdjVal     = Math::BigFloat->new($adjustedVal);

        #look for a rolled counter
        if ( $counterbits and $bigAdjVal < $bigPrevVal ) {

            #the counter has rolled
            print localtime
              . " - Detected rolled counter for $metricName: Doing $bigAdjVal += $bigCounterMax = ";
            $bigAdjVal->badd($bigCounterMax);
            print "$bigAdjVal\n";

            my $tempPrev     = $bigPrevVal;
            my $tempAdj      = $bigAdjVal;
            my $tempTimeDiff = $timestamp - $prevValHash->{'timestamp'};

            print localtime . " - Doing $tempAdj - $tempPrev = ";
            $tempAdj->bsub($tempPrev);
            print "$tempAdj\n";

            print localtime . " - Doing $tempAdj / $tempTimeDiff = ";
            $tempAdj->bdiv($tempTimeDiff);
            print "$tempAdj\n";

        }

        my $timeDiff = $timestamp - $prevValHash->{'timestamp'};
        $bigAdjVal->bsub($bigPrevVal);

        if ( $bigAdjVal and $bigAdjVal->is_pos() and $timeDiff ) {

            $bigAdjVal->bdiv($timeDiff);
            $mungedResult = $bigAdjVal->bstr();

        }
        elsif ( $bigAdjVal->is_neg() ) {
            print
"WARNING: processing $metricName, $adjustedVal - $prevValHash->{'value'} = $bigAdjVal\n";
        }
        else {
            $mungedResult = '0';
        }

    }
    else {
        #if we cant do the calc because we dont have the previous
        #val, set the value to undef.  If this goes to graphite it
        #will show a gap in the graph which is more appropriate than
        #showing zero or something.
    }

    $self->_storeCache( $metricName,
        { 'value' => $value, 'timestamp' => $timestamp } );

    return $mungedResult;
}

=head3 asPercentage()

  Takes the value and a max value, calculates the percentage of the max
  represented by value and returns the result.

=cut

sub asPercentage {
    my $self   = shift;
    my $result = $self->{'data'};
    my $mungedResult;

    unless ( $result->{'max'} ) {

        #this result set does not support this munge function
        return $result->{'value'};
    }

    my $value = Math::BigFloat->new( $result->{'value'} );
    my $max   = Math::BigFloat->new( $result->{'max'} );

    if ( $value->is_pos() ) {
        $value->bdiv($max);
        $value->bmul(100);

        #convert the bigint back to a string
        $mungedResult = $value->bstr();
    }
    else {
        #avoid divide by zero
        $mungedResult = '0';
    }

    return $mungedResult;
}

=head3 changeSinceLast()

  The changeSinceLast method compares the current result with the
  previous one and calculates the difference resulting in the number of
  counts during the time period.

  changeSinceLast = <result> - <prev._result>

  The method also considers counter roll (where the counter reaches its
  maximum value and restarts from zero) by checking to see if the new
  result is less than the previous result. If so, the counters max value
  (2 ** counter_bits) is added to the new result to reveal the true
  value for the purposes of the above calculation.

  changeSinceLast = (<result> + <counter_max>) - <prev._result>

  Note that it is still
  the raw result that is stored in memcached for use in the next iteration.

  TODO: Counters will also reset to zero on a reboot.  Need to also get
  and compare system uptime to dectect this scenario, and manage it
  appropriately.

=cut

sub changeSinceLast {
    my $self   = shift;
    my $result = $self->{'data'};
    my $mungedResult;

    #pull some vars for convieniance
    my $value       = $result->{'value'};
    my $adjustedVal = $value;
    my $timestamp   = $result->{'timestamp'};
    my $target      = $result->{'target'};
    my $device      = $result->{'device'};
    my $metric      = $result->{'metric'};
    my $counterbits = $result->{'counterbits'};

    #Build a fully qualified metric name for memcached storage.
    my $metricName = $target . '.' . $device . '.' . $metric;
    $metricName =~ s/\s/_/g;    #remove any spaces

    #get the value from the previous run
    my $prevValHash = $self->_getCache($metricName);

    if ($prevValHash) {

        #Create Bigint Objects
        my $bigCounterMax = Math::BigFloat->bpow( 2, $counterbits );
        my $bigPrevVal    = Math::BigFloat->new( $prevValHash->{'value'} );
        my $bigAdjVal     = Math::BigFloat->new($adjustedVal);

        #look for a rolled counter
        if ( $counterbits and $bigAdjVal < $bigPrevVal ) {

            #the counter has rolled
            print localtime
              . " - Detected rolled counter for $metricName: Doing $bigAdjVal += $bigCounterMax = ";

            $bigAdjVal->badd($bigCounterMax);

            print "$bigAdjVal\n";
        }

        $bigAdjVal->bsub($bigPrevVal);

        if ($bigAdjVal) {
            if ( $bigAdjVal->is_neg() ) {
                print
"WARNING: processing $metricName, $adjustedVal - $prevValHash->{'value'} = $bigAdjVal\n";
            }

            $mungedResult = $bigAdjVal->bstr();
        }
        else {
            $mungedResult = '0';
        }

    }
    else {
        #if we cant do the calc because we dont have the previous
        #val, set the value to undef.  If this goes to graphite it
        #will show a gap in the graph which is more appropriate than
        #showing zero or something.
    }

    $self->_storeCache( $metricName,
        { 'value' => $value, 'timestamp' => $timestamp } );

    return $mungedResult;
}

=head3 availToUsed()

  Implemented to support memory usage due to snmp providing the avail
  memory as opposed to used.  This method uses the total memory and
  the avail memory to calculate the used mem.

  Used = Total - Avail.

=cut

sub availToUsed {
    my $self   = shift;
    my $result = $self->{'data'};
    my $mungedResult;

    unless ( $result->{'max'} ) {

        #this result set does not support this munge function
        return $result->{'value'};
    }

    my $value = $result->{'value'};
    my $max   = $result->{'max'};

    $mungedResult = $max - $value;

    return $mungedResult;
}

### Private Subs ###

sub _storeCache {
    my $self    = shift;
    my $keyName = shift;
    my $value   = shift;

    my $cacheObj = $self->{'cacheObj'};

    if ( $cacheObj->set( $keyName, $value ) ) {
        return 1;
    }

    print "Couldnt store $value\n";

    return;
}

sub _getCache {
    my $self    = shift;
    my $keyName = shift;

    my $cacheObj = $self->{'cacheObj'};

    my $val = $cacheObj->get($keyName);

    return $val if $val;

    return;
}

1;
