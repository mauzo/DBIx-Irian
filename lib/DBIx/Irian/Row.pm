package DBIx::Irian::Row;

use warnings;
use strict;

use parent "DBIx::Irian::QuerySet";

use DBIx::Irian   undef, qw(
    trace tracex
    install_sub register lookup find_sym load_class qualify
);

no overloading;
use overload
    q/@{}/      => sub { $_[0][1] },
    fallback    => 1;

sub _DB { $_[0][0] }

sub _new {
    my ($class, $db, $row, $names) = @_;
    if (my $inf = lookup $class, "inflate") {
        # copy, since peek might give us more than one Row for this
        # fetched row. Ideally that should be fixed...
        $row = [
            map $inf->[$_] ? $inf->[$_]->($row->[$_]) : $row->[$_],
                0..$#$row
        ];
    }

    tracex {
        my $cols = lookup $class, "cols" || ["!!!"];
        $names ||= ["???"];
        "CLASS [$class]",
        "REG'D COLS [@$cols]",
        "SQL COLS [@$names]",
        "VALUES [@$row]",
    } "ROW";

    bless [$db, $row], $class;
}

our %SUGAR = (
    columns => sub {
        my @mycols = @_;
        my $pkg = caller;

        tracex { "COLUMNS [$pkg]: [@mycols]" } "ROW";
        register $pkg, mycols => \@mycols;

        my $parents = lookup($pkg, "extends") || [];
        my @inherit = map @{ lookup($_, "cols") || [] }, @$parents;

        tracex { "INHERIT [$pkg] COLUMNS [@inherit]" } "ROW";
        register $pkg, cols => [ @inherit, @_ ];

        my @inf;
        for (@$parents) {
            my $cols = lookup($_, "cols")       || [];
            my $inf  = lookup($_, "inflate")    || [];

            # make sure we get enough entries to cover all the columns
            push @inf, @$inf[0..$#$cols];
        }

        tracex { "INHERIT [$pkg] INFLATE [@inf]" } "ROW";
        register $pkg, inflate => \@inf;

        for my $ix (0..$#_) {
            install_sub $pkg, $_[$ix], sub { $_[0][1][$ix + @inherit] };
        }
    },

    extends => sub {
        my @ext = @_;
        my $pkg = caller;

        lookup $pkg, "cols" and Carp::croak
            "'extends' must come before 'columns'";

        tracex { "EXTENDS: [$pkg] [@ext]" } "ROW";

        my @ps = map load_class($pkg, $_, "Row"), @ext;
        register $pkg, extends => \@ps;

        tracex { "EXTENDS: [$pkg] [@ps]" } "ROW";
    },

    inflate => sub {
        my (%inf) = @_;
        my $pkg = caller;

        tracex { 
            my @inf = map "$_|$inf{$_}", keys %inf;
            "INFLATE [$pkg]: [@inf]" 
        } "ROW";

        my $mycols = lookup $pkg, "mycols" or Carp::croak 
            "'inflate' must come after 'columns'";
        
        my $inf = lookup $pkg, "inflate";
        $inf or register $pkg, inflate => ($inf = []);

        push @$inf, DBIx::Irian::Inflate->lookup($inf{$_})
            for @$mycols;
    },

);

1;
