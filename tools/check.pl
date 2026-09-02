#!/usr/bin/perl
# Perl mirror of tools/check.py for machines without Python.
# Block balance per .lua file + manifest drift on a full run.
use strict; use warnings;
my @files = @ARGV ? @ARGV : sort glob("*.lua");
my $ok = 1;
for my $path (@files) {
  open(my $fh, '<:encoding(UTF-8)', $path) or die "$path: $!";
  my ($depth, $bad, $n) = (0, 0, 0);
  while (my $line = <$fh>) {
    $n++;
    my $code = $line;
    $code =~ s/--.*//;
    $code =~ s/"([^"\\]|\\.)*"/""/g;
    $code =~ s/'([^'\\]|\\.)*'/''/g;
    while ($code =~ /\b(function|if|do|repeat|until|end)\b/g) {
      my $tok = $1;
      $depth += ($tok =~ /^(function|if|do|repeat)$/) ? 1 : -1;
      if ($depth < 0) { print "$path: UNDERFLOW at line $n: $line"; $bad = 1; }
    }
  }
  close $fh;
  my $good = ($depth == 0 && !$bad);
  $ok = 0 unless $good;
  printf "%-24s %-8s %4d lines%s\n", $path, ($good ? "OK" : "DEPTH $depth"), $n,
         ($n > 200 ? "  (over 200 -- consider splitting)" : "");
}
if (!@ARGV) {
  my %listed;
  open(my $m, '<', 'beefiles.txt') or do { print "beefiles.txt: MISSING\n"; exit 1 };
  while (my $l = <$m>) {
    $l =~ s/^\s+|\s+$//g; next if $l eq '' || $l =~ /^#/;
    my @p = split /\s+/, $l;
    if (@p < 2 || $p[1] !~ m{^/}) { print "beefiles.txt: bad line: $l\n"; $ok = 0; next; }
    $listed{$p[0]} = $p[1];
  }
  for my $src (sort keys %listed) { unless (-e $src) { print "beefiles.txt: lists $src, not in repo\n"; $ok = 0; } }
  for my $f (sort glob("*.lua")) {
    next if $f eq 'beebot.lua';
    unless ($listed{$f}) { print "beefiles.txt: does not list $f\n"; $ok = 0; }
  }
  printf "%-24s %-8s %4d entries\n", 'beefiles.txt', ($ok ? 'OK' : 'DRIFT'), scalar keys %listed;
}
exit($ok ? 0 : 1);
