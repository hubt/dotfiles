#!/usr/bin/perl

print "== Vendor ==\n";
print `dmidecode | grep "Product Name"`;
print "== CPUs ==\n";
print `cat /proc/cpuinfo | egrep '(processor|model name)'`;
print "== Distro ==\n";
print `cat /etc/*release`;
print "== Kernel ==\n";
print `cat /proc/version`;
print "== Memory(MB) ==\n";
print `grep MemTotal /proc/meminfo`;
print "== Disks ==\n";
print `df -h`;
print "== listening ==\n";
print `netstat -l | grep tcp`;
print "== DNS ==\n";
print `grep hosts /etc/nsswitch.conf`;
print `grep nameserver /etc/resolv.conf`;
print "== services ==\n";
print `service --status-all | grep '+'`;
