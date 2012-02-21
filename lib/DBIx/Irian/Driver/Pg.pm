package DBIx::Irian::Driver::Pg;

use warnings;
use strict;

use parent "DBIx::Irian::Driver";
use DBIx::Irian undef, "tracex";

sub init { $_[0]{gensym} = 0 }
sub gensym { "irian_cursor_" . $_[0]{gensym}++ }

sub cursor {
    my ($self, $sql, $bind) = @_;

    my $cursor = $self->gensym;
    my $declare = "DECLARE $cursor CURSOR WITH HOLD FOR $sql";
    
    tracex { "[$declare] [@$bind]" } "SQL";
    $self->dbh->do($declare, undef, @$bind)   or return;

    return $cursor;
}

sub fetch {
    my ($self, $cursor, $n) = @_;
    my $fetch = "FETCH $n FROM $cursor";

    tracex { "[$fetch]" } "SQL";
    my $rs = $self->dbh->selectall_arrayref($fetch);
    @$rs or return;
    return $rs;
}

sub close {
    my ($self, $cursor) = @_;
    my $close = "CLOSE " . $cursor;
    tracex { "[$close]" } "SQL";
    $self->dbh->do($close);
}

1;

