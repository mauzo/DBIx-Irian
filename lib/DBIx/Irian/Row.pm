package DBIx::Irian::Row;

use warnings;
use strict;

use parent "DBIx::Irian::HasDB";

use DBIx::Irian   undef, qw(
    install_sub register lookup find_sym row_class
);

sub _DB { $_[0][0] }

sub _new { bless [$_[1], $_[2]], $_[0] }

our %SUGAR = (
    columns => sub {
        my $pkg = caller;
        my $parents = lookup($pkg, "extends") || [];
        my @inherit = map @{ lookup($_, "cols") }, @$parents;
        register $pkg,
            type    => "row",
            cols    => [ @inherit, @_ ];
        for my $ix (0..$#_) {
            install_sub $pkg, $_[$ix], sub { $_[0][1][$ix + @inherit] };
        }
    },

    extends => sub {
        my $pkg = caller;
        lookup $pkg, "cols" and Carp::croak
            "'extends' must come before 'columns'";

        my @ps = map row_class($pkg, $_), @_;
        register $pkg, extends => \@ps;

        local $" = "][";
        warn "EXTENDS: [$pkg] [@ps]\n";

        my $isa = find_sym $pkg, '@ISA';
        # XXX I don't entirely like this... what we don't want to end up
        # with is
        #   @Foo::ISA = qw/DBIx::Irian::Row/;
        #   @Bar::ISA = qw/DBIx::Irian::Row Foo/;
        # since that way Bar will resolve methods in ::Row before Foo,
        # which is wrong. Nevertheless, I don't quite like mucking about
        # with @ISA like this.
        @$isa = (grep($_ ne __PACKAGE__, @$isa), @ps);
    },

);

1;
