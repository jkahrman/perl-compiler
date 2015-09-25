#!./perl

# This script tests the inlining and prototype of CORE:: subs.  Any generic
# tests that are not specific to &foo-style calls should go in this
# file, too.

BEGIN {
    push @INC, qw{t/CORE/lib};
    require "t/CORE/test.pl";
    skip_all_without_dynamic_extension('B');
    $^P |= 0x100;
}

use B::Deparse;
my $bd = new B::Deparse '-p';

my %unsupported = map +($_=>1), qw (
 __DATA__ __END__ AUTOLOAD BEGIN UNITCHECK CORE DESTROY END INIT CHECK and
  cmp default do dump else elsif eq eval for foreach
  format ge given goto grep gt if last le local lt m map my ne next
  no  or  our  package  print  printf  q  qq  qr  qw  qx  redo  require
  return s say sort state sub tr unless until use
  when while x xor y
);
my %args_for = (
  dbmopen  => '%1,$2,$3',
 (dbmclose => '%1',
  keys     =>
  values   =>
  each     =>)[0,1,2,1,3,1,4,1],
  delete   => '$1[2]',
  exists   => '$1[2]',
 (push     => '@1',
  pop      =>
  shift    =>
  unshift  =>
  splice   =>)[0,1,2,1,3,1,4,1,5,1],
);
my %desc = (
  pos => 'match position',
);

use File::Spec::Functions;
chdir 't/CORE/op';
my $keywords_file = catfile(updir,'lib','keywords.pl');
open my $kh, $keywords_file
   or die "$0 cannot open $keywords_file: $!";
while(<$kh>) {
  if (m?__END__?..${\0} and /^[+-]/) {
    chomp(my $word = $');
    if($unsupported{$word}) {
      $tests ++;
      ok !defined &{"CORE::$word"}, "no CORE::$word";
    }
    else {
      $tests += 4;

      ok defined &{"CORE::$word"}, "defined &{'CORE::$word'}";

      my $proto = prototype "CORE::$word";
      *{"my$word"} = \&{"CORE::$word"};
      is prototype \&{"my$word"}, $proto, "prototype of &CORE::$word";

      CORE::state $protochar = qr/([^\\]|\\(?:[^[]|\[[^]]+\]))/;
      my $numargs =
            $word eq 'delete' || $word eq 'exists' ? 1 :
            (() = $proto =~ s/;.*//r =~ /\G$protochar/g);
      my $code =
         "#line 1 This-line-makes-__FILE__-easier-to-test.
          sub { () = (my$word("
             . ($args_for{$word} || join ",", map "\$$_", 1..$numargs)
       . "))}";
      my $core = $bd->coderef2text(eval $code =~ s/my/CORE::/r or die);
      my $my   = $bd->coderef2text(eval $code or die);
      is $my, $core, "inlinability of CORE::$word with parens";

      $code =
         "#line 1 This-line-makes-__FILE__-easier-to-test.
          sub { () = (my$word "
             . ($args_for{$word} || join ",", map "\$$_", 1..$numargs)
       . ")}";
      $core = $bd->coderef2text(eval $code =~ s/my/CORE::/r or die);
      $my   = $bd->coderef2text(eval $code or die);
      is $my, $core, "inlinability of CORE::$word without parens";

      # High-precedence tests
      my $hpcode;
      if (!$proto && defined $proto) { # nullary
         $hpcode = "sub { () = my$word + 1 }";
      }
      elsif ($proto =~ /^;?$protochar\z/) { # unary
         $hpcode = "sub { () = my$word "
                           . ($args_for{$word}||'$a') . ' > $b'
                       .'}';
      }
      if ($hpcode) {
         $tests ++;
         $core = $bd->coderef2text(eval $hpcode =~ s/my/CORE::/r or die);
         $my   = $bd->coderef2text(eval $hpcode or die);
         is $my, $core, "precedence of CORE::$word without parens";
      }

      next if ($proto =~ /\@/);
      # These ops currently accept any number of args, despite their
      # prototypes, if they have any:
      next if $word =~ /^(?:chom?p|exec|keys|each|not
                           |(?:prototyp|read(?:lin|pip))e
                           |reset|system|values|l?stat)|evalbytes/x;

      $tests ++;
      $code =
         "sub { () = (my$word("
             . (
                $args_for{$word}
                 ? $args_for{$word}.',$7'
                 : join ",", map "\$$_", 1..$numargs+5+(
                      $proto =~ /;/
                       ? () = $' =~ /\G$protochar/g
                       : 0
                   )
               )
       . "))}";
      eval $code;
      my $desc = $desc{$word} || $word;
      like $@, qr/^Too many arguments for $desc/,
          "inlined CORE::$word with too many args"
        or warn $code;

    }
  }
}

$tests++;
# This subroutine is outside the warnings scope:
sub foo { goto &CORE::abs }
use warnings;
$SIG{__WARN__} = sub { like shift, qr\^Use of uninitialized\ };
foo(undef);

$tests+=2;
is runperl(prog => 'print CORE->lc, qq-\n-'), "core\n",
 'methods calls autovivify coresubs';
is runperl(prog => '@ISA=CORE; print main->uc, qq-\n-'), "MAIN\n",
 'inherted method calls autovivify coresubs';

{ # RT #117607
  $tests++;
  like runperl(prog => '$foo/; \&CORE::lc', stderr => 1),
    qr/^syntax error/, "RT #117607: \\&CORE::foo doesn't crash in error context";
}

$tests++;
ok eval { *CORE::exit = \42 },
  '[rt.cpan.org #74289] *CORE::foo is not accidentally made read-only';

@UNIVERSAL::ISA = CORE;
is "just another "->ucfirst . "perl hacker,\n"->ucfirst,
   "Just another Perl hacker,\n", 'coresubs do not return TARG';
++$tests;

done_testing $tests;

CORE::__END__
