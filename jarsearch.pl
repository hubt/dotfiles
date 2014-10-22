#!/usr/bin/perl

$class = shift;
$class =~ s#/#.#g;

if ( $ENV{CLASSPATH} ) {
  print "Using CLASSPATH\n$ENV{CLASSPATH}\n";
  @cp = split(":",$ENV{CLASSPATH});
} else {
  $cmd = "locate --regex '\\.jar\$'";
  print "Searching for jars with $cmd\n";
  @cp = `$cmd`;
}

print "Searching " . scalar(@cp) . " jar files for $class\n";

for my $jar ( @cp ) {
  chomp($jar);
  $out = `jar -tf $jar | grep $class 2>&1`;
  if ( $? ) {
    #print "Error in jar: $jar\n$out\n";
  } elsif ( $out ) {
    print "$jar:\n$out\n";
  }
}

