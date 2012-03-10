package DBIx::Irian::Row::Generic;

use warnings;
use strict;

use Carp ();

# set up ISA explicitly, since I don't want Irian to start trying to
# register this class against a DB
use parent "DBIx::Irian::Row";
use DBIx::Irian undef, qw"trace tracex";

# I'm seriously reconsidering the @{} overload...
no overloading;

sub _new {
    my ($class, $db, $row, $cols) = @_;
    tracex { 
        my $c = $cols || ["???"];
        my $r = $row || ["???"];
        "CLASS [$class]",
        "SQL COLS [@$c]",
        "VALUES [@$r]",
    } "ROW";
    my %cols = map +($$cols[$_] => $_), 0..$#$cols;
    bless [$db, $row, \%cols], $class;
}

sub DESTROY { }

# Meh. Don't like this, but trying to get ->{UNIVERSAL,SUPER,Row}::can
# to give the right answers seems to be annoyingly difficult.
my %Methods = map +($_, 1), qw(
    _DB _new DESTROY AUTOLOAD
    isa can DOES VERSION
);

sub can {
    my ($self, $col) = @_;

    trace ROW => "GENERIC CAN [$col]";

    # overload methods, among other things
    $col =~ /\W/ || $Methods{$col}
        and return $self->UNIVERSAL::can($col);
    ref $self                   or return;
    defined $self->[2]{$col}    or return;

    # this will create and cache an AUTOLOADable stub
    no strict "refs";
    \&$col;
}

our $AUTOLOAD;
sub AUTOLOAD {
    my ($self) = @_;
    (my $col = $AUTOLOAD) =~ s/.*:://;
    my $ix = $self->[2]{$col};
    defined $ix or Carp::croak "No such column '$col'";
    trace ROW => "GENERIC AUTOLOAD [$col] [$ix]";
    $self->[1][$ix];
}

1;
