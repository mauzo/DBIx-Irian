package DBIx::OQM::Cursor;

use warnings;
use strict;

use parent "DBIx::OQM::HasDB";

use Carp;
use DBIx::OQM   undef, qw/install_sub/;

for my $n (qw/_DB sth row/) {
    install_sub $n, sub { $_[0]{$n} };
}

sub next {
    my ($self) = @_;
    my $rs = $self->{_rows};
    unless ($rs and @$rs) {
        my $sth = $self->sth;
        $sth->{Active} or return;
        $rs = $self->{_rows} = $sth->fetchall_arrayref;
    }
    $rs and @$rs or return;
    bless [$self->_DB, shift @$rs], $self->row;
}

1;
