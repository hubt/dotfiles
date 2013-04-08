#!/usr/bin/perl
$infile = shift;
$outfile = shift;
die "Usage: bigsort <inputfile> <outputfile>" if ( !$infile || !$outfile);

$splitlines = 10*1000*1000;
$processors = `grep -c processor /proc/cpuinfo`;
chomp($processors);

$tmpdir = ".";
$size = -s $infile;
$free = `df $tmpdir`;
($vol,$blocks,$used,$avail,$pct,$mount) =~ split(/\w+/,$free);
if ( $avail < 2* $size ) {
  warn "Warning: tempdir $tmpdir requires 2x free space of size of the input file ";
}
$free = `df $outfile`;
($vol,$blocks,$used,$avail,$pct,$mount) =~ split(/\w+/,$free);
if ( $avail < $size ) {
  warn "Warning: output may fail due to free space $avail available, $size required";
}


print "Splitting file $infile into directory $tmpdir\n";
print `split -l $splitlines $infile`;
@files = <$infile.??>;
print "Sorting " . scalar(@files). " individual files with $processors concurrent sorts\n";
print `echo @files | xargs -n 1 -P $processors sort -o {}.sorted {}`;
print "Deleting unsorted files\n";
unlink @files;
print "Doing final merge\n";
for(@files) {
  push(@sorted,"$_.sorted");
}
print "Doing final merge\n";
print `sort -o $outfile -m @files`;

