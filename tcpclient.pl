#!/usr/bin/perl
use IO::Socket;
use lib 'lib';
use Time::HiRes qw(gettimeofday);
#$host  = "sfman1";
$host   = shift;
$port   = shift || 8000;
$bufsize= 1024*1024;
$send   = 10;

if ( !defined $host || !defined $port ) {
  print "Usage: tcpclient.pl <host> [port]\n";
}

print "Connecting\n";
$remote = IO::Socket::INET->new(
                        Proto    => "tcp",
                        PeerAddr => $host,
                        PeerPort => $port
                    )
                  or die "cannot connect $!";
print "Connected\n";
#print $remote "GET / HTTP/1.0\n\n"; while(<$remote>) { print ; } exit;
($start,$ustart) = gettimeofday;
print "Start time: " . localtime($start) . "\n";
$buf = "0" x $bufsize;
for(1..$send) {
  print $remote $buf;
}
($end,$uend) = gettimeofday;
print "End time  : " . localtime($end) . "\n";
($end,$uend) = gettimeofday;
$timediff = ($end-$start) + (($uend-$ustart)/1000_000);
print "Time      : " . ($timediff) . "\n";
print "Rate      : " . ($bufsize*$send)/((1024*1024)*($timediff)) . " MB/s\n";
