#!/usr/bin/perl

use JSON::PP;
# args are NAME=VALUE tags
use Getopt::Long;
my $csv;
GetOptions('csv' =>\$csv);

if ( !@ARGV) {
  die "Usage: $0 TAGNAME=VALUE [ .. TAGNAME=VALUE] # tags are ANDED together ";
}
$tag = "";
for(@ARGV) {
  my ($k,$v) = split(/=/);
  $tags{$k} = $v;
}

$tag = join(" ", map { "Name=tag:$_,Values=$tags{$_}" } keys %tags);
#JSON::PP
$out = `aws ec2 describe-instances --filters $tag`;
$j = decode_json($out);

my @list;
for $r (@{$j->{Reservations}}){
  for $i (@{$r->{Instances}}) {
    #my @fields = ($i->{PublicDnsName},$i->{PublicIpAddress},$i->{PrivateIpAddress});
    #my @fields = ($i->{PublicIpAddress});
    push(@list,$i->{PublicIpAddress});
  }
}

if ( $csv ) {
  print join(",",@list). "\n";
} else {
  print join("\n",@list). "\n";
}

