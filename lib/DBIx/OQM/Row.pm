package DBIx::OQM::Row;

use warnings;
use strict;

use parent "DBIx::OQM::HasDB";

use DBIx::OQM   undef, qw/install_sub register/;

sub _DB { $_[0][0] }

our %SUGAR = (
    columns => sub {
        my $pkg = caller;
        register $pkg,
            type    => "row",
            cols    => [ @_ ];
        for my $ix (0..$#_) {
            install_sub $pkg, $_[$ix], sub { $_[0][1][$ix] };
        }
    },
);

1;
