package B::OP;

use B qw/peekop/;
use B::C::File qw/objsym savesym svsect save_rv init copsect opsect/;

sub save {
    my ( $op, $level ) = @_;

    my $sym = objsym($op);
    return $sym if defined $sym;
    my $type = $op->type;
    $B::C::nullop_count++ unless $type;
    if ( $type == $B::C::OP_THREADSV ) {

        # saves looking up ppaddr but it's a bit naughty to hard code this
        init()->add( sprintf( "(void)find_threadsv(%s);", cstring( $threadsv_names[ $op->targ ] ) ) );
    }
    if ( $type == $B::C::OP_UCFIRST ) {
        $B::C::fold = 1;

        warn "enabling -ffold with ucfirst\n" if B::C::verbose();
        require "utf8.pm" unless $B::C::savINC{"utf8.pm"};
        require "utf8_heavy.pl" unless $B::C::savINC{"utf8_heavy.pl"};    # bypass AUTOLOAD
        mark_package("utf8");
        mark_package("utf8_heavy.pl");

    }
    if ( ref($op) eq 'B::OP' ) {    # check wrong BASEOPs
                                    # [perl #80622] Introducing the entrytry hack, needed since 5.12, fixed with 5.13.8 a425677
                                    #   ck_eval upgrades the UNOP entertry to a LOGOP, but B gets us just a B::OP (BASEOP).
                                    #   op->other points to the leavetry op, which is needed for the eval scope.
        if ( $op->name eq 'entertry' ) {
            warn "[perl #80622] Upgrading entertry from BASEOP to LOGOP...\n" if B::C::verbose();
            bless $op, 'B::LOGOP';
            return $op->save($level);
        }
    }

    # since 5.10 nullified cops free their additional fields
    if ( !$type and $OP_COP{ $op->targ } ) {
        warn sprintf( "Null COP: %d\n", $op->targ ) if $B::C::debug{cops};

        copsect()->comment("$opsect_common, line, stash, file, hints, seq, warnings, hints_hash");
        copsect()->add(
            sprintf(
                "%s, 0, %s, NULL, 0, 0, NULL, NULL",
                $op->_save_common, B::C::USE_ITHREADS ? "(char *)NULL" : "Nullhv"
            )
        );

        my $ix = copsect()->index;
        init()->add( sprintf( "cop_list[$ix].op_ppaddr = %s;", $op->ppaddr ) )
          unless $B::C::optimize_ppaddr;
        savesym( $op, "(OP*)&cop_list[$ix]" );
    }
    else {
        opsect()->comment($opsect_common);
        opsect()->add( $op->_save_common );

        opsect()->debug( $op->name, $op );
        my $ix = opsect()->index;
        init()->add( sprintf( "op_list[$ix].op_ppaddr = %s;", $op->ppaddr ) )
          unless $B::C::optimize_ppaddr;
        warn(
            sprintf(
                "  OP=%s targ=%d flags=0x%x private=0x%x\n",
                peekop($op), $op->targ, $op->flags, $op->private
            )
        ) if $B::C::debug{op};
        savesym( $op, "&op_list[$ix]" );
    }
}

# See also init_op_ppaddr below; initializes the ppaddr to the
# OpTYPE; init_op_ppaddr iterates over the ops and sets
# op_ppaddr to PL_ppaddr[op_ppaddr]; this avoids an explicit assignment
# in perl_init ( ~10 bytes/op with GCC/i386 )
sub fake_ppaddr {
    return "NULL" unless $_[0]->can('name');
    return $B::C::optimize_ppaddr
      ? sprintf( "INT2PTR(void*,OP_%s)", uc( $_[0]->name ) )
      : ( $verbose ? sprintf( "/*OP_%s*/NULL", uc( $_[0]->name ) ) : "NULL" );
}
sub B::FAKEOP::fake_ppaddr { "NULL" }

# XXX HACK! duct-taping around compiler problems
sub isa { UNIVERSAL::isa(@_) }    # walkoptree_slow misses that
sub can { UNIVERSAL::can(@_) }

1;