package DBIx::Irian::Driver::Pg;

use warnings;
use strict;

use parent "DBIx::Irian::Driver";

use Carp                qw/croak/;
use DBIx::Irian undef, "tracex";

sub init { $_[0]{gensym} = 0 }
sub gensym { "irian_cursor_" . $_[0]{gensym}++ }

sub _do {
    my ($dbh, $trc, $sql, @bind) = @_;
    tracex { "[$sql] [@bind]" } $trc;
    $dbh->do($sql, undef, @bind);
}

sub cursor {
    my ($self, $sql, $bind) = @_;

    my $cursor = $self->gensym;
    my $declare = "DECLARE $cursor CURSOR WITH HOLD FOR $sql";
    
    _do $self->dbh, "CUR", $declare, @$bind or return;

    return $cursor;
}

sub fetch {
    my ($self, $cursor, $n) = @_;
    my $fetch = "FETCH $n FROM $cursor";

    tracex { "[$fetch]" } "CUR";
    my $rs = $self->dbh->selectall_arrayref($fetch);
    @$rs or return;
    return $rs;
}

sub close {
    my ($self, $cursor) = @_;
    my $close = "CLOSE " . $cursor;
    _do $self->dbh, "CUR", $close;
}

sub txn_set_mode {
    my ($self, $dbh, $conf) = @_;
    
    if (defined(my $ro = $$conf{readonly})) {
        my $access = $ro ? "READ ONLY" : "READ WRITE";
        _do $dbh, "TXN", "SET TRANSACTION $access";
    }
    if (defined(my $iso = $$conf{isolation})) {
        $iso =~ /^read (?:un)?committed|repeatable read|serializable$/i
            or croak "Bad txn isolation level '$iso'";
        _do $dbh, "TXN", "SET TRANSACTION ISOLATION LEVEL $iso";
    }
    if (defined(my $defer = $$conf{pg_defer})) {
        my $not = $defer ? "" : "NOT ";
        _do $dbh, "TXN", "SET TRANSACTION ${not}DEFERRABLE";
    }

    return;
}

sub txn_restore_mode { croak "Driver::Pg doesn't need txn_restore_mode" }

sub txn_recover {
    my ($self, $dbh, $conf, $info) = @_;

    $info->{state} eq "40001" or return;
    $dbh->rollback;
    return 1;
}

1;

