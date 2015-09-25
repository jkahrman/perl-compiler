#!./perl -w

BEGIN {
    push @INC, "t/CORE/lib";
    require 't/CORE/test.pl';
    skip_all_without_config('d_setpgrp');
}

plan tests => 3;

ok(!eval { package A;sub foo { die("got here") }; package main; A->foo(setpgrp())});
ok($@ =~ /got here/, "setpgrp() should extend the stack before modifying it");

is join("_", setpgrp(0)), 1, 'setpgrp with one argument';
