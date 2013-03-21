#!/usr/bin/perl

@var = qw(
  url_effective
  http_code
  http_connect
  time_total
  time_namelookup
  time_connect
  time_pretransfer
  time_redirect
  time_starttransfer
  size_download
  size_upload
  size_header
  size_request
  speed_download
  speed_upload
  content_type
  num_connects
  num_redirects
  ftp_entry_path
);

for(sort @var) {
  $w .= "$_=\%{$_}\n";
}
print `curl -o /dev/null -v -w "$w" @ARGV`;
