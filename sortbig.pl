#!/usr/bin/perl

#this is untested

$infile = shift;
$outfile = shift;
die "Usage: bigsort <inputfile> <outputfile>" if ( !$infile || !$outfile);

$splitlines = 100000;
$tmpdir = ".";
$sortargs = "";



$processors = `grep -c processor /proc/cpuinfo`;
chomp($processors);

sub roll_file {
  $filename = "$infile.part.$filenum";
  push(@files,"$filename.sorted");
  open(PART,">$infile.part.$filenum") || die;
  $filenum++;
}

print "Splitting file $infile into directory $tmpdir with max lines $splitlines\n";
open(SORTS,"| xargs -i -n 1 -P $processors sh -c 'sort -o {}.sorted {}; rm {}'") || die;
open(IN,"<$infile") || die;
$filenum = 0;
$linecount = 0;

roll_file();
print SORTS "$filename\n";
while(<IN>) {
  print PART $_;
  if ( $linecount++ > $splitlines ) {
    roll_file();
    print SORTS "$filename\n";
    $linecount = 0;
  }
}
close(PART);
close(SORTS);
    
print "Waiting for sorts of " . scalar(@files). " individual files with $processors concurrent sorts\n";
print "Doing final merge\n";
print `sort -o $outfile -m @files`;
print "Deleting temp files\n";
for(@files) {
  unlink $_;
}
