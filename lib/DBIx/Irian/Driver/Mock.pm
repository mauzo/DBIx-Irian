package DBIx::Irian::Driver::Mock;

use warnings;
use strict;

use parent "DBIx::Irian::Driver";
use DBIx::Irian undef, "tracex";

sub cursor {
    my ($self, $sql, $bind) = @_;

    my $declare = "DECLARE $sql";
    
    tracex { "[$declare] [@$bind]" } "SQL";
    $self->dbh->do($declare, undef, @$bind)   or return;

    return $sql;
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
    my $close = "CLOSE $cursor";

    tracex { "[$close]" } "SQL";
    $self->dbh->do($close);
}

1;

