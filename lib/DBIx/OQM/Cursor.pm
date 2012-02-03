package DBIx::OQM::Cursor;

use warnings;
use strict;

use DBIx::OQM::Util qw/install_sub/;

for my $n (qw/_DB sth/) {
    install_sub $n, sub { $_[0]{$n} };
}

sub next {
    my ($self) = @_;
    warn "$self->next";
    my $r = \$self->{rows};
    if ($$r and @$$r) {
        shift @$$r;
    }
    else {
        $$r = $self->sth->fetchall_arrayref;
    }
    return !!@$$r;
}

1;
