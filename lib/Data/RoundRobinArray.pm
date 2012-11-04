#!/usr/bin/false

package Data::RoundRobinArray;

use strict;
use warnings;

my $NUM_REGEX = qr(^\d+(?:\.\d+)?$);

sub new {
    my $class = shift;
    my $elements = shift || die 'Must supply number of elements';

    unless ( $elements =~ /^\d+$/ and $elements > 0 ) {
        die 'Elements must be a number greater than 0';
    }

    $class = ref $class || $class;

    my %objHash = (
        'elements' => $elements,
        'nextIdx'  => 0,
        'lastIdx'  => undef,
        'array'    => [],
    );

    my $object = bless \%objHash, $class;

    return $object;
}

sub add {
    my $self   = shift;
    my $newVal = shift;
    
    chomp($newVal);

    #Where to put the new value
    my $idx = $self->{'nextIdx'};

    #add the new value
    $self->{'array'}->[$idx] = $newVal;

    #increment the index counters
    $self->{'nextIdx'}++;
    defined $self->{'lastIdx'}
      ? ( $self->{'lastIdx'}++ )
      : ( $self->{'lastIdx'} = 0 );

    #Roll the index counters if need be
    if ( $self->{'nextIdx'} > $self->{'elements'} - 1 ) {
        $self->{'nextIdx'} = 0;
    }
    if ( $self->{'lastIdx'} > $self->{'elements'} - 1 ) {
        $self->{'lastIdx'} = 0;
    }

    $self->_validateArray();

    return 1;
}

sub updateIndex {
    # hmm because the array rolls, should the index refer to the index
    # relative to where the next idx is, or should it be the hard index?
    my $self = shift;
    my $idx  = shift;
    my $val  = shift; #may be undef
    
    chomp($idx);
    chomp($val);
    
    unless ( $idx and ( $idx >= 0 and $idx <= $#{$self->{'array'}} ) ) {
        die "First arg to updateIndex must be a number between 0 and the higest index in the array\n";
    }
    
    $self->{'array'}->[$idx] = $val;
    
    $self->_validateArray();
    
    return 1;
}
    

sub getArray {
	my $self    = shift;
	my @array   = @{$self->{'array'}};
	my $next    = $self->{'nextIdx'};
	my $last    = $self->{'lastIdx'};
	my $lastIdx = $#{$self->{'array'}};
	
	my @realArray;
	if ($next == 0) {
	    @realArray = @array[$next..$lastIdx];
	}
	else {
		@realArray = @array[$next..$lastIdx,0..$last];
	}	
	
	return wantarray ? @realArray : \@realArray;
}

sub largest {
    my $self = shift;
    my $code = shift;
	my @array = $self->sorted($code);
    
    return $array[-1];
}
	
sub smallest {
    my $self = shift;
    my $code = shift;
	my @array = $self->sorted($code);
    
    return $array[0];
}

sub average {
	my $self = shift;
	my $code = shift;
	my @array = $self->getArray();
	
	my $total;
	my $count;
	
	for my $val ( @array ) {
		#we can only care about numbers.
		$val = $self->_extractNumber($val, $code) or next;
		
		$total += $val;
		$count++;
	}
	
    unless ( defined $total and defined $count ) {
        return;
    }
    
	if ( $total and $count ) {
		return ($total / $count);
	}
	elsif ( $total == 0 or $count == 0 ) {
        return 0;		
	}
	
	return;
}

sub total {
	my $self = shift;
	my $code = shift;
	my @array = $self->getArray();
	
	my $total;
	
	for my $val ( @array ) {
		#we can only care about numbers.
		$val = $self->_extractNumber($val, $code) or next;
		
		$total += $val;
	}
	
    return $total;	
}

sub clear {
	my $self = shift;
	
    $self->{'nextIdx'} = 0;
	$self->{'lastIdx'} = undef;
	$self->{'array'}   = [];

    return 1;
}

sub sorted {
	my $self  = shift;
	my $code  = shift;
	my @array = @{$self->{'array'}};
	my @sorted;
	
    if ( $code ) {
        if ( $code and ref($code) eq 'CODE' ) {
            @sorted = sort { $a <=> $b }
                      grep { defined $_ and /$NUM_REGEX/ } 
                      map  { defined $_ and $code->($_) }  @array;
        }
        elsif ( not ref $code or ref $code eq 'Regexp' ) {
            $code = qr($code) unless ref $code;
            @sorted = sort { $a <=> $b }
                      grep { defined $_ and /$NUM_REGEX/ } 
                      map  { defined $_ and $_ =~ $code ? $& : $_ }  @array;
        }
    } 
    else {
        @sorted = sort { $a <=> $b } 
                  grep { /$NUM_REGEX/ } @array;
    }
	
	return wantarray ? @sorted : \@sorted;
}

sub _validateArray {
	my $self = shift;
	
	if ( scalar @{$self->{'array'}} > $self->{'elements'} ) {
		die "The array has somehow gotten bigger than the number of elements. This is a bug!\n";
	}
	
	return 1;
}

sub _extractNumber {
    my $self = shift;
    my $val  = shift || return;
    my $code = shift;
    
 	if ($code) {
        if (ref $code eq 'CODE') {
            #use the suppled code ref to extract a number.
            eval {
                $val = $code->($val);
            };
            if ( $@ ) {
                die "Code reference provided to average() died: $!\n";
            }
        }
        elsif ( not ref $code or ref $code eq 'Regexp' ) {
            #Try using the value of code as a regex
            $code = qr($code) unless ref $code;
            if ( $val =~ $code ) {
                $val = $&;
            }
            elsif ( $val =~ $NUM_REGEX ) {
                # The contents of $code wasnt a sub ref and we didnt
                # match it using $code as a regex.  However, $val is
                # a number anyway and so we'll use it.  But given
                # that a $code value was supplied and was not
                # effective, this may be errornous. Warn on it.
                warn "The code argument had no effect on $val, but seeing as its a number we'll use it anyway.  Should the code arg have done something?\n";
            }
        }
    }

    return $val if $val =~ $NUM_REGEX;
    return;
}

1;
