#!/usr/bin/perl

use JSON::PP;
# args are NAME=VALUE tags
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

for $r (@{$j->{Reservations}}){
  for $i (@{$r->{Instances}}) {
    #my @fields = ($i->{PublicDnsName},$i->{PublicIpAddress},$i->{PrivateIpAddress});
    my @fields = ($i->{PublicIpAddress});
    print "@fields\n";
  }
}

  

