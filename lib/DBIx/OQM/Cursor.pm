package DBIx::OQM::Cursor;

use warnings;
use strict;

use DBIx::OQM::Util qw/install_sub/;

for my $n (qw/_DB/) {
    install_sub $n, sub { $_[0]{$n} };
}

1;
