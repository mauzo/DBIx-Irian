package DBIx::Irian::DB;

use warnings;
use strict;

use parent "DBIx::Irian::QuerySet";

use Carp                qw/carp croak/;
use Scalar::Util        qw/reftype/;
use Try::Tiny;
#use Data::Dump          qw/pp/;

use DBIx::Irian         undef, qw(
    install_sub trace tracex expand_query lookup
);
use DBIx::Connector;
use DBIx::Irian::Driver;

BEGIN { our @CLEAN = qw/
    reftype carp croak pp try catch finally
    merge_txnmode
/ }

push @Data::Dump::FILTERS, sub {
    my ($ctx, $obj) = @_;
    $ctx->object_isa(__PACKAGE__) or return;
    my %hv = %{$obj};
    delete @hv{qw/dbc dbh _DB driver/};
    { dump => $ctx->class . Data::Dump::pp(\%hv) };
};

for my $n (qw/
    dsn user password dbi mode txnmode
    dbcclass dbc driver _DB
    in_txn
/) {
    install_sub $n, sub { $_[0]{$n} };
}

my %TxnMode = (
    no_ping     => [mode        => "no_ping"            ],
    ping        => [mode        => "ping"               ],
    fixup       => [mode        => "fixup"              ],
    ro          => [readonly    => 1                    ],
    rw          => [readonly    => 0                    ],
    uncommit    => [isolation   => "READ UNCOMMITTED"   ],
    commit      => [isolation   => "READ COMMITTED"     ],
    repeatable  => [isolation   => "REPEATABLE READ"    ],
    serial      => [isolation   => "SERIALIZABLE"       ],
    require     => [require     => 1                    ],
);

sub merge_txnmode {
    my ($c, $d) = @_;
    if (ref $c) {
        $c = { %$c };
    }
    else {
        $c = {
            map @{ $TxnMode{$_} || [] },
            split /,/, 
            $c // ""
        };
    }
    exists $$c{$_} or $$c{$_} = $$d{$_}
        for keys %$d;

    # special cases
    $$c{err_info} //= sub {
        # Default DBI RaiseError exceptions
        my ($dbh, $err) = @_;
        !ref $err && $err =~ /^DBD::/ or return;
        $dbh->err or return;  
        return {
            err     => $dbh->err,
            errstr  => $dbh->errstr,
            state   => $dbh->state,
        };
    };
    unless (ref $$c{err_info}) {
        # Exception::Class::DBI-compatible exceptions
        my $class = $$c{err_info};
        $$c{err_info} = sub {
            my (undef, $err) = @_;
            eval { $err->isa($class) } or return;
            return {
                err     => $err->err,
                errstr  => $err->errstr,
                state   => $err->state,
            };
        };
    }

    return $c;
}

sub new {
    my ($class, @args) = @_;
    my %self = @args == 1 
        ? ref $args[0]
            ? %{$args[0]}
            : (dsn => @args)
        : @args;

    $self{dbcclass}         ||= "DBIx::Connector";

    $self{dbi}{AutoCommit}  //= 1;
    grep exists($self{dbi}{$_}), qw/RaiseError HandleError/
        or $self{dbi}{RaiseError} = 1;

    $self{mode}             ||= "no_ping";
    $self{txnmode}  = merge_txnmode $self{txnmode}, 
        { mode => $self{mode} };

    $self{dbc}              ||= $self{dbcclass}->new(
        @self{qw/dsn user password dbi/}
    );
    $self{driver}           ||= DBIx::Irian::Driver->new($self{dbc});

    $self{dbc}->mode($self{mode});

    $self{_DB} = bless \%self, $class;
}

sub dbh { $_[0]->dbc->dbh }

sub _check_txn_compat { }

sub _check_in_txn { 
    my $require = $_[0]->txnmode->{require};
    !$require || $_[0]->in_txn
        or ($require eq "warn" ? \&carp : \&croak)->
            ("Not in a transaction");
}

for my $m (qw/svp txn/) {
    install_sub $m, sub {
        my $self = shift;
        my $conf = @_ > 1 && shift;
        my $cb   = shift;

        $conf = merge_txnmode $conf, $self->txnmode;

        if (my $old = $self->in_txn) {
            $self->_check_txn_compat($conf, $old);
            $self->dbc->$m($conf->{mode}, $cb);
        }
        else {
            $self->_start_txn($conf, $cb);
        }
    };
}

sub _start_txn {
    my ($self, $conf, $cb) = @_;

    local $self->{in_txn} = $conf;

    RETRY_TXN: {
        $self->dbc->txn($conf->{mode}, sub {
            my $dbh = $_;
            my $restore = $self->driver->txn_set_mode($dbh, $conf);

            # The return value of the try is returned from this sub,
            # from dbc->txn, from the RETRY loop, and from $self->txn.
            # The context is equivalently passed down to the callback.
            try { $cb->() }
            catch {
                my $info = $conf->{err_info}->($dbh, $_);
                $self->driver->txn_recover($dbh, $conf, $info) 
                    or die $_;
                trace TXN => "RETRYING [$$info{errstr}]";
                no warnings "exiting";
                redo RETRY_TXN;
            }
            finally {
                $restore and
                    $self->driver->txn_restore_mode($dbh, $restore);
            };
        });
    }
}

sub do_expand_query {
    my ($self, $row, $query, $args) = @_;
    $args = 
        ref $args ?
            reftype $args eq "ARRAY"    ? $args         :
            reftype $args eq "HASH"     ? [ %$args ]    :
            croak("Bad reftype '$args'")                :
        [];
    tracex {
        require Data::Dump;
        "DO EXPAND [$row][$query] " . Data::Dump::pp({@$args});
    } "EXP";
    expand_query $query, {
        @$args,
        db  => $self,
        row => $row,
    };
}

sub do_query {
    my ($self, $row, $query, $args) = @_;
    my ($sql, @bind) = $self->do_expand_query($row, $query, $args);

    $self->_check_in_txn;
    my ($cols, $rows) = $self->dbc->run(sub {
        tracex { "[$sql] [@bind]" } "SQL";

        my $sth = $_->prepare($sql);
        $sth->execute(@bind) or return;

        ($sth->{NAME}, $sth->fetchall_arrayref);
    });
    $rows and @$rows or return;

    tracex {
        my $regd = lookup($row, "cols");
        "CLASS [$row]",
        ($regd ? "COLS [@$regd]"
            : "SQL COLS [@$cols]"
        ),
    } "ROW";

    wantarray and return map $row->_new($self, $_, $cols), @$rows;

    @$rows == 1 or carp "Query [$sql] returned more than one row";
    $row->_new($self, $rows->[0], $cols);
}

sub do_cursor {
    my ($self, $row, $query, $args) = @_;
    my ($sql, @bind) = $self->do_expand_query($row, $query, $args);

    DBIx::Irian::Cursor->new(
        DB      => $self,
        sql     => $sql,
        bind    => \@bind,
        row     => $row,
    );
}

sub do_detail {
    my ($self, $query, $args) = @_;
    my ($sql, @bind) = $self->do_expand_query(undef, $query, $args);

    $self->_check_in_txn;
    my $rows = $self->dbc->run(sub {
        tracex { "[$sql] [@bind]" } "SQL";
        my $sth = $_->prepare($sql);
        $sth->execute(@bind);
        $sth->fetchall_arrayref;    
    });
    $rows or return;

    my @rows = map $$_[0], @$rows;
    tracex { "DETAIL [@rows]" } "ROW";
    @rows or return;
    wantarray and return @rows;

    @rows == 1 or carp "Query [$sql] returned more than one row";
    $rows[0];
}

sub do_action {
    my ($self, $query, $args) = @_;
    my ($sql, @bind) = $self->do_expand_query(undef, $query, $args);

    $self->_check_in_txn;
    $self->dbc->run(sub {
        tracex { "[$sql] [@bind]" } "SQL";
        $_->do($sql, undef, @bind);
    });
}

1;
