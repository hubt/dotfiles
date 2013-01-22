#!/usr/bin/perl

# takes a set of key, values 
# assumes each key will have multiple numeric values, and for each key, will print out the nth percentiles
# prints out sorted by alphanumeric key
# key count sum percentiles
# by default 50th % and 95th%

use Getopt::Long;
@percentiles;
$perlout = 0;
$headers = 1;
$separator = "\t";
$full = 0;
GetOptions(
  "p=i" => \@percentiles,
  "perlout" => \$perlout,
  "headers!" => \$headers,
  "separator" => \$separator,
  "full" => \$full
);
if (!@percentiles) {
  @percentiles = qw( 50 95 );
}

while(<>) {
  ($key,$value) = split;
  push(@{$data->{$key}->{values}},$value);
}

if ( !$perlout && $headers ) {
  print join($separator,"name","count","avg","sum",@percentiles)."\n";
}

for $key ( sort keys %$data ) {
  @{$data->{$key}->{values}} = sort {$a <=> $b} @{$data->{$key}->{values}};
  @values = @{$data->{$key}->{values}};
  my @row;
  my $sum = 0;
  for(@values) { $sum += $_ };
  my $avg = $sum/scalar(@values);
  for $p (@percentiles) {
    my $pvalue = $values[int(scalar(@values)*($p/100))];
    push(@row,$pvalue);
    if ( $perlout ) {
      $data->{$key}->{"percent$p"} = $pvalue;
    }
  }
  if ( $perlout ) {
    $data->{$key}->{count} = scalar(@values);
    $data->{$key}->{sum} = $sum;
    $data->{$key}->{avg} = $avg;
  } else {
    print join($separator,$key,scalar(@values),$avg,$sum,@row) . "\n";
  }

  if ( !$full ) {
    delete $data->{$key}->{values};
  }
}

if ($perlout) {
  use Data::Dumper;
  print Dumper(\$data);
}
