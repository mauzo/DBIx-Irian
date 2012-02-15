package DBIx::Irian::Row;

use warnings;
use strict;

use parent "DBIx::Irian::QuerySet";

use DBIx::Irian   undef, qw(
    install_sub register lookup find_sym load_class qualify
);

no overloading;
use overload
    q/@{}/      => sub { $_[0][1] },
    fallback    => 1;

sub _DB { $_[0][0] }

sub _new {
    my ($class, $db, $row) = @_;
    if (my $inf = lookup $class, "inflate") {
        $inf->[$_] and $row->[$_] = $inf->[$_]->($row->[$_])
            for 0..$#$row;
    }
    bless [$db, $row], $class;
}

our %SUGAR = (
    columns => sub {
        my $pkg = caller;

        register $pkg, mycols => [ @_ ];

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

    inflate => sub {
        my (%inf) = @_;
        my $pkg = caller;

        local $" = "][";
        warn "INFLATE [$pkg]: [@_]\n";

        my $mycols = lookup $pkg, "mycols" or Carp::croak 
            "'inflate' must come after 'columns'";
        my @inf;

        my $parents = lookup($pkg, "extends")   || [];
        for (@$parents) {
            my $cols = lookup($_, "cols")       || [];
            my $inf  = lookup($_, "inflate")    || [];

            # make sure we get enough entries to cover all the columns
            push @inf, @$inf[0..$#$cols];
        }

        push @inf, DBIx::Irian::Inflate->lookup($inf{$_})
            for @$mycols;

        register $pkg, inflate => \@inf;
    },

);

1;
