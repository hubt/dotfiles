#!/usr/bin/perl

use JSON::PP;
use Data::Dumper;
use Getopt::Long;

$config_file = "firewall.json";
GetOptions(
  "file=s" => \$config_file
);

sub load_file {
  my $f = shift;
  local $/ = undef;
  open( my $fh, '<', $f );
  $json_text = <$fh>;
  $config = decode_json($json_text);
}

if ( scalar(@ARGV) == 1 ) {
  @hosts = @ARGV;
  load_file($config_file);
} elsif ( scalar(@ARGV) == 2 ) {
  @hosts = ($ARGV[0]);
  $onedest = $ARGV[1];
} else {
  load_file($config_file);
  @hosts = sort keys %{$config->{hosts}};
}

for(sort keys %{$config->{services}}) {
  $revservices{$config->{services}->{$_}} = $_;
}

for $h (@hosts) {
  my @services;
  if ( $onedest ) {
    @services = ($onedest);
  } else {
    @services = @{$config->{hosts}->{$h}};
  }
  for $s (@services) {
    if ( $config->{services}->{$s} ) {
      $dest = $config->{services}->{$s};
    } else {
      $dest = $s;
    }
    $name = $revservices{$dest};
    ($destname,$port) = split(/:/,$dest);
    if ( $port <= 0 ) {
      die "Must specify <hostname:port> in $destname";
    }
    if ( $h !~ /(\d+).(\d+).(\d+).(\d+)/ ) {
      $sourceip = `dig +search +short $h`;
      chomp($sourceip);
    } else {
      $sourceip = $h;
    }
    if ( $destname !~ /(\d+).(\d+).(\d+).(\d+)/ ) {
      $destip = `dig +search +short $destname`;
      chomp($destip);
    } else {
      $destip = $destname;
    }
    print "Testing host $h connection to service $name($dest) [ source=$sourceip dest=$destip:$port ]:  ";
    print `ssh $h 'nmap -P0 -p $port $destip | grep $port'`;
  }
}
  
