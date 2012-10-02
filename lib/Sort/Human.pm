#!/usr/bin/false

=head1 NAME

Sort::Human

=head1 DESCRIPTION

Provides some alternate functions for sorting lists in ways that are
more natural to the way people generally sort items.

Perl traditionally provides two types of sort. Numeric (<=>) which when
given a list of numbers will sort them numerically the way you would
expect and alphanumeric which sorts into alphabetical order.  The issue
arises when list items are a mix of numbers and letters.  In this case
it we really have to use an alphanumeric sort which follows the standard
method of comparing the letters and numbers one at a time.  Which 
results in the following examples:

  abc123
  abc124
  acc123
  acc124 <-- pretty normal so far...
  add1
  add10
  add2   <-- Huh? Isn't 2 < 10? Yes, but that's not the comparison perl
             makes because it isnt comparing numbers but rather strings
             and thus after comparing the 2nd 'd' without determining
             a result (they're both the same to that point), instead of
             comparing 2 and 10, it actually only compares 2 and 1.
             1 < 2 and therefore add10 comes before add2.
             
Sort::Human will try to sort the list in such a way that add2 (read
add-two) comes before add10 (read add-ten, not add-1-0).

=head1 SYNOPSIS
  
  #use the module and import the desired functions if desired.
  use Sort::Human qw(sortCaseInsensitive);
  
  my @list = ( 'item 1', 'item 10', 'item 2' );
  
  my @sorted = sortCaseInsensitive(@list);
  
  print "@sorted\n";
  # item 1 item 2 item 10

=head1 EXPORTS

Exports the following functions on request.  None are exported by
default.

sortCaseInsensitive()
sortCaseSensitive()
sortCaseInsensitiveBlock()
sortCaseSensitiveBlock()

=head1 FUNCTIONS
=cut


package Sort::Human;

    use strict;
    use warnings;
    use Exporter 'import';
    
    our @EXPORT_OK = qw( sortCaseInsensitive
                         sortCaseSensitive
                         sortCaseInsensitiveBlock
                         sortCaseSensitiveBlock
                       );

=head2 sortCaseInsensitive

Requires a list of items to sort or a reference to an array containing
the items to sort.

Returns a list or reference to a list depending on the calling context
sorted naturally ignoring case.  I.e. 'a' eq 'A'.

=cut

    sub sortCaseInsensitive {
        my $list = ref $_[0] ? shift : \@_;
        ref $list eq 'ARRAY'
          or die "sortCaseInsensitive reqires an list or array reference\n";

        my @return = sort { _doSort($a, $b, 1) } @{$list};
        
        return wantarray ? @return : \@return;
    }

=head2 sortCaseSensitive

Requires a list of items to sort or a reference to an array containing
the items to sort.

Returns a list or reference to a list depending on the calling context
sorted naturally case sensitivity.  I.e. 'a' > 'A'.

=cut

    sub sortCaseSensitive {
        my $list = ref $_[0] ? shift : \@_;
        ref $list eq 'ARRAY'
          or die "sortCaseSensitive reqires an list or array reference\n";
        
        my @return = sort { _doSort($a, $b) } @{$list};
        
        return wantarray ? @return : \@return;
    }

=head2 sortCaseInsensitiveBlock

Requires 2 scalars to compare and determine order.  This function is
provided to be used in a sort() block so that if the items in your list
to sort are complex data structures and you wish to sort based on a
particular value in those structures you can do so.  E.g. Assume a list
of array refs and we want to sort the outer list based on the first
element of each inner array:
  
  my @list = ( ['item 1',  'item '1], 
               ['item 10', 'item '2], 
               ['item 2',  'item '3], 
             );
  my @sorted = sort { sortCaseInsensitiveBlock($a->[0],$b->[0]) } @list;
  
  print Dumper(\@sorted);
  
  # $VAR1 = ( 
  #           ['item 1',  'item '1], 
  #           ['item 2',  'item '3], 
  #           ['item 10', 'item '2], 
  #         );

Returns a list or reference to a list depending on the calling context
sorted naturally with case insensitivity.  I.e. 'a' eq 'A'.

=cut
    
    sub sortCaseInsensitiveBlock {
        my $a = shift;
        my $b = shift;
    
        unless ($a and $b) {
            die "sortCaseInsensitiveBlock requires 2 arguments\n";
        }
       
        my $result = _doSort($a, $b, 1);
        
        return $result;
    }

=head2 sortCaseSensitiveBlock

Requires 2 scalars to compare and determine order.  This function is
provided to be used in a sort() block so that if the items in your list
to sort are complex data structures and you wish to sort based on a
particular value in those structures you can do so.  E.g. Assume a list
of array refs and we want to sort the outer list based on the first
element of each inner array:
  
  my @list = ( ['item 1',  'item '1], 
               ['item 10', 'item '2], 
               ['item 2',  'item '3], 
             );
  my @sorted = sort { sortCaseInsensitiveBlock($a->[0],$b->[0]) } @list;
  
  print Dumper(\@sorted);
  
  # $VAR1 = ( 
  #           ['item 1',  'item '1], 
  #           ['item 2',  'item '3], 
  #           ['item 10', 'item '2], 
  #         );

Returns a list or reference to a list depending on the calling context
sorted naturally with case sensitivity.  I.e. 'a' > 'A'.

=cut

    sub sortCaseSensitiveBlock {
        my $a = shift;
        my $b = shift;
    
        unless ($a and $b) {
            die "sortCaseInsensitiveBlock requires 2 arguments\n";
        }
       
        my $result = _doSort($a, $b);
        
        return $result;
    }
    
    #private.  Implements the actual sorting logic.
    sub _doSort {
        my $a = shift;
        my $b = shift;
        
        my $caseInsen = shift;
        
        if ($caseInsen) {
            $a = lc($a);
            $b = lc($b);
        }
        
        if ($a eq $b) {
            return 0;
        }

        my @aElems = split //, $a;
        my @bElems = split //, $b;
        
        my $length = ($#aElems > $#bElems) ? $#aElems : $#bElems;
        my $i = 0;
        
        while ( $i <= $length ) {
            #check to see if both have bee the same to this point but one
            #has stopped
            unless (defined $aElems[$i]) {
                return -1;
            }
            unless (defined $bElems[$i]) {
                return 1;
            }
            
            #If both the current positions are numbers. Look ahead for the
            #full number and do a numerical sort.
            if ( $aElems[$i] =~ /\d/ and $bElems[$i] =~ /\d/ ) {
                my $aRemainder = join('', @aElems[$i..$#aElems] );
                my $bRemainder = join('', @bElems[$i..$#bElems] );
                
                my ($aNum) = $aRemainder =~ /^(\d+(?:\.\d+)?)/;
                my ($bNum) = $bRemainder =~ /^(\d+(?:\.\d+)?)/;
                
                #If the numbers are diff, determine the sort order using
                #numerical sort and return.
                unless ( $aNum == $bNum ) {
                    return ($aNum <=> $bNum);
                }

                #Skip to the end of the numbers.                
                $i += length $aNum;
                
            }
            else {
                unless ($aElems[$i] eq $bElems[$i]) {
                    return ( $aElems[$i] cmp $bElems[$i] );			 
                }
                $i ++;
            }
        }
        
        die "Couldnt compare\n";
    }
1;
