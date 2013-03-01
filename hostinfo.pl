#!/usr/bin/perl

print "== Vendor ==\n";
print `dmidecode | grep "Product Name"`;
print "== CPUs ==\n";
print `cat /proc/cpuinfo | grep processor | tail -1`;
print "== Memory(MB) ==\n";
print `free -mt | grep Total`;
print "== Disks ==\n";
print `df -h`;
