#! /usr/bin/env perl
# http://code.google.com/p/perl-compiler/issues/detail?id=245
# unicode value not preserved when passed to a function with -O3
use strict;
BEGIN {
  unshift @INC, 't';
  require "test.pl";
}
use Test::More tests => 1;

use B::C;
# passes threaded and <5.10
my $fixed_with = "1.42_71";
my $TODO = "TODO " if $B::C::VERSION lt $fixed_with;
$TODO = "" if $Config{useithreads};
$TODO = "" if $] < 5.010;
my $todomsg = '#245 unicode arg not-threaded -O3';
ctest(1,"b: 223", 'C,-O3','ccode245i', <<'EOF', $TODO.$todomsg);
sub foo {
    my ( $a, $b ) = @_;
    print "b: ".ord($b);
}
foo(lc("\x{1E9E}"), "\x{df}");
EOF
