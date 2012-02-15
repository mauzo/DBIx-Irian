package DBIx::Irian::Row;

use warnings;
use strict;

use parent "DBIx::Irian::QuerySet";

use DBIx::Irian   undef, qw(
    install_sub register lookup find_sym load_class
);

no overloading;
use overload
    q/@{}/      => sub { $_[0][1] },
    fallback    => 1;

sub _DB { $_[0][0] }

sub _new { bless [$_[1], $_[2]], $_[0] }

our %SUGAR = (
    columns => sub {
        my $pkg = caller;
        my $parents = lookup($pkg, "extends") || [];
        my @inherit = map @{ lookup($_, "cols") || [] }, @$parents;
        register $pkg, cols => [ @inherit, @_ ];
        for my $ix (0..$#_) {
            install_sub $pkg, $_[$ix], sub { $_[0][1][$ix + @inherit] };
        }
    },

    extends => sub {
        my $pkg = caller;
        lookup $pkg, "cols" and Carp::croak
            "'extends' must come before 'columns'";

        warn "EXTENDS: [$pkg] [@_]\n";

        my @ps = map load_class($pkg, $_, "Row"), @_;
        register $pkg, extends => \@ps;

        local $" = "][";
        warn "EXTENDS: [$pkg] [@ps]\n";
    },

);

1;
