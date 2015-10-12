package B::COP;

use strict;

use B qw/cstring/;
use B::C::Config;
use B::C::File qw/init copsect/;
use B::C::Save qw/constpv savestash_flags savestashpv/;
use B::C::Decimal qw/get_integer_value/;
use B::C::Helpers::Symtable qw/savesym objsym/;
use B::C::Helpers qw/read_utf8_string strlen_flags/;

sub save {
    my ( $op, $level ) = @_;

    my $sym = objsym($op);
    return $sym if defined $sym;

    # we need to keep CvSTART cops, so check $level == 0
    if ( $B::C::optimize_cop and $level and !$op->label ) {    # XXX very unsafe!
        my $sym = savesym( $op, $op->next->save );
        debug(
            cops => "Skip COP (0x%x) => %s (0x%x), line %d file %s\n",
            $$op, $sym, $op->next, $op->line, $op->file
        );
        return $sym;
    }

    # TODO: if it is a nullified COP we must save it with all cop fields!
    debug( cops => "COP: line %d file %s\n", $op->line, $op->file );

    # shameless cut'n'paste from B::Deparse
    my $warn_sv;
    my $warnings   = $op->warnings;
    my $is_special = ref($warnings) eq 'B::SPECIAL';
    my $warnsvcast = "(STRLEN*)";
    if ( $is_special && $$warnings == 4 ) {    # use warnings 'all';
        $warn_sv = 'pWARN_ALL';
    }
    elsif ( $is_special && $$warnings == 5 ) {    # no warnings 'all';
        $warn_sv = 'pWARN_NONE';
    }
    elsif ($is_special) {                         # use warnings;
        $warn_sv = 'pWARN_STD';
    }
    else {
        # LEXWARN_on: Original $warnings->save from 5.8.9 was wrong,
        # DUP_WARNINGS copied length PVX bytes.
        my $warn = bless $warnings, "B::LEXWARN";
        $warn_sv = $warn->save;
        my $ix = copsect()->index + 1;

        # XXX No idea how a &sv_list[] came up here, a re-used object. Anyway.
        $warn_sv = substr( $warn_sv, 1 ) if substr( $warn_sv, 0, 3 ) eq '&sv';
        $warn_sv = $warnsvcast . '&' . $warn_sv;
        free()->add( sprintf( "    cop_list[%d].cop_warnings = NULL;", $ix ) )
          if !$B::C::optimize_warn_sv;

        #push @B::C::static_free, sprintf("cop_list[%d]", $ix);
    }

    my $dynamic_copwarn = !$is_special ? 1 : !$B::C::optimize_warn_sv;

    # Trim the .pl extension, to print the executable name only.
    my $file = $op->file;

    # $file =~ s/\.pl$/.c/;

    if ( USE_ITHREADS() ) {
        copsect()->comment_common("line, stashoff, file, hints, seq, warnings, hints_hash");
        copsect()->add(
            sprintf(
                "%s, %u, " . "%d, %s, %u, " . "%s, %s, NULL",
                $op->_save_common, $op->line,
                $op->stashoff,     "NULL",      #hints=0
                $op->hints,
                ivx( $op->cop_seq ), !$dynamic_copwarn ? $warn_sv : 'NULL'
            )
        );
    }
    else {
        # cop_label now in hints_hash (Change #33656)
        copsect()->comment_common("line, stash, file, hints, seq, warn_sv, hints_hash");
        copsect()->add(
            sprintf(
                "%s, %u, " . "%s, %s, %u, " . "%s, %s, NULL",
                $op->_save_common, $op->line,

                # we cannot store this static (attribute exit)
                "Nullhv", "Nullgv",
                $op->hints, get_integer_value( $op->cop_seq ), !$dynamic_copwarn ? $warn_sv : 'NULL'
            )
        );
    }

    if ( $op->label ) {

        # test 29 and 15,16,21. 44,45
        my ( $cstring, $cur, $utf8 ) = strlen_flags( $op->label );
        init()->add(
            sprintf(
                "Perl_cop_store_label(aTHX_ &cop_list[%d], %s, %u, %s);",
                copsect()->index, $cstring, $cur, $utf8
            )
        );

    }

    copsect()->debug( $op->name, $op );
    my $ix = copsect()->index;
    init()->add( sprintf( "cop_list[$ix].op_ppaddr = %s;", $op->ppaddr ) )
      unless $B::C::optimize_ppaddr;
    if ( !$is_special ) {
        my $copw = $warn_sv;
        $copw =~ s/^\(STRLEN\*\)&//;

        # on cv_undef (scope exit, die, ...) CvROOT and all its kids are freed.
        # lexical cop_warnings need to be dynamic, but just the ptr to the static string.
        if ($copw) {
            my $dest = "cop_list[$ix].cop_warnings";

            # with DEBUGGING savepvn returns ptr + PERL_MEMORY_DEBUG_HEADER_SIZE
            # which is not the address which will be freed in S_cop_free.
            # Need to use old-style PerlMemShared_, see S_cop_free in op.c (#362)
            # lexwarn<n> might be also be STRLEN* 0
            init()->add("$dest = (STRLEN*)savesharedpvn((const char*)$copw, sizeof($copw));");
        }
    }
    else {
        init()->add( sprintf( "cop_list[$ix].cop_warnings = %s;", $warn_sv ) )
          unless $B::C::optimize_warn_sv;
    }

    if ( !$B::C::optimize_cop ) {
        my $name = $op->stashpv;
        if ( !USE_ITHREADS() ) {
            if ($B::C::const_strings) {

                # QUESTION: use length on the non const and save it with const, could the len be incorrect ?
                my ( $pv, $len, $flags ) = strlen_flags( $op->stashpv );
                my $stash = savestash_flags( constpv( $op->stashpv ), $len, $flags );
                my $constpv = constpv($file);
                init()->add(
                    sprintf( "CopSTASH_set(&cop_list[%d], %s);", $ix, $stash ),
                    sprintf( "CopFILE_set(&cop_list[%d], %s);",  $ix, $constpv )
                );
            }
            else {
                my $stash = savestashpv( $op->stashpv );
                init()->add(
                    sprintf( "CopSTASH_set(&cop_list[%d], %s);", $ix, $stash ),
                    sprintf( "CopFILE_set(&cop_list[%d], %s);",  $ix, cstring($file) )
                );
            }
        }
        else {    # cv_undef e.g. in bproto.t and many more core tests with threads
            my $stash = savestashpv( $op->stashpv );
            init()->add(
                sprintf( "CopSTASH_set(&cop_list[%d], %s);", $ix, $stash ),
                sprintf( "CopFILE_set(&cop_list[%d], %s);", $ix, cstring($file) )
            );
        }
    }

    # our root: store all packages from this file
    if ( !$B::C::mainfile ) {
        $B::C::mainfile = $op->file if $op->stashpv eq 'main';
    }
    else {
        B::C::mark_package( $op->stashpv ) if $B::C::mainfile eq $op->file and $op->stashpv ne 'main';
    }
    savesym( $op, "(OP*)&cop_list[$ix]" );
}

1;