#!/usr/bin/perl -w
use IO::Socket;
use Net::hostent;              # for OO version of gethostbyaddr

$port = 8000;                  # pick something not in use

$server = IO::Socket::INET->new( Proto     => 'tcp',
			  LocalPort => $port,
			  Listen    => SOMAXCONN,
			  Reuse     => 1);

die "can't setup server" unless $server;
$sock = $server->accept();
while(<$sock>) {
}
if ( $! ) {
  print $!;
}

