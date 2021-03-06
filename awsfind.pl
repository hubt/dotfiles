#!/usr/bin/perl

use JSON::PP;
$json = JSON::PP->new;
$json->canonical(1);
# args are NAME=VALUE tags
use Getopt::Long;
my $allips,$csv,$one,$private,$public,$raw,$info,$id;
GetOptions(
  '1' => \$one,
  'allips' => \$allips,
  'csv' =>\$csv,
  'id' => \$id,
  'private' => \$private,
  'public' => \$public,
  'info' => \$info,
  'raw' => \$raw
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
$cmd= "aws ec2 describe-instances --output json --filters Name=instance-state-name,Values=running $tag";
#print("$cmd\n");
$out = `$cmd`;
$j = decode_json($out);
if ( $raw ) {
  print $out;
  exit;
}
my @list;
for $r (@{$j->{Reservations}}){
  for $i (@{$r->{Instances}}) {
    #my @fields = ($i->{PublicDnsName},$i->{PublicIpAddress},$i->{PrivateIpAddress});
    #my @fields = ($i->{PublicIpAddress});
    if ($allips || ($private && $public)) {
      push(@list,"$i->{PublicIpAddress}:$i->{PrivateIpAddress}");
    } elsif ( $private ) {
      push(@list,$i->{PrivateIpAddress});
    } elsif ( $id ) {
      push(@list,$i->{InstanceId});
    } elsif ( $info ) {
      @fields=("PublicIpAddress","PrivateIpAddress","InstanceType","InstanceId");
      $r = {};
      for(@fields) { 
         $r->{$_} = $i->{$_};
      }
      my @tags;
      for(@{$i->{Tags}}) {
        push(@tags,"$_->{Key}=$_->{Value}");
      }
      $r->{Tags} = join(",",sort @tags);
      #use Data::Dumper;
      #print(Dumper($r));
      #print(join(" ",sort keys %
      push(@list,$json->encode($r));
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

