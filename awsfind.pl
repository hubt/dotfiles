#!/usr/bin/perl

use JSON::PP;
# args are NAME=VALUE tags
use Getopt::Long;
my $allips,$csv,$one,$private,$public;
GetOptions(
  '1' => \$one,
  'allips' => \$allips,
  'csv' =>\$csv,
  'private' => \$private,
  'public' => \$public
);

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
    if ($allips || ($private && $public)) {
      push(@list,"$i->{PublicIpAddress}:$i->{PrivateIpAddress}");
    } elsif ( $private ) {
      push(@list,$i->{PrivateIpAddress});
    } else {
      push(@list,$i->{PublicIpAddress});
    }
  }
}

@list = sort @list;
if ( $one ) {
  @list = shift @list;
}
if ( $csv ) {
  print join(",",@list). "\n";
} else {
  print join("\n",@list). "\n";
}

