#!/usr/bin/perl

`/home/hubt/bin/xsltproc resume.xsl resume.xml > resume.html`;
`links -dump resume.html > resume.txt`;
#`wget -O resume.pdf 'http://www.easysw.com/htmldoc/pdf-o-matic.php?URL=http://www.chen.net/~hubt/resume/resume.html'`;

