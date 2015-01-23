#!/usr/bin/perl

for(1..64*1024) {
  open($fds[$_],">/dev/null") || die "Failed to open " . ($_+3) . " file descriptors";
}

