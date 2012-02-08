package DBIx::Irian::Driver::Pg;

use warnings;
use strict;

use parent "DBIx::Irian::Driver";

sub init { $_[0]{gensym} = 0 }
sub gensym { "oqm_cursor_" . $_[0]{gensym}++ }

sub cursor {
    my ($self, $sql, $bind) = @_;

    my $cursor = $self->gensym;
    my $declare = "DECLARE $cursor CURSOR WITH HOLD FOR $sql";
    
    local $" = "][";
    warn "SQL: [$declare] [@$bind]\n";
    $self->dbh->do($declare, undef, @$bind)   or return;

    return $cursor;
}

sub fetch {
    my ($self, $cursor, $n) = @_;
    my $fetch = "FETCH $n FROM $cursor";

    warn "SQL: [$fetch]\n";
    my $rs = $self->dbh->selectall_arrayref($fetch);
    @$rs or return;
    return $rs;
}

sub close {
    my ($self, $cursor) = @_;
    my $close = "CLOSE " . $cursor;
    warn "SQL: [$close]\n";
    $self->dbh->do($close);
}

1;

