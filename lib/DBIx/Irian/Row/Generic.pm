package DBIx::Irian::Row::Generic;

=head1 NAME

DBIx::Irian::Row::Generic - Generic AUTOLOADed Row class

=head1 SYNOPSIS

    package My::DB;
    use DBIx::Irian "DB";

    query foo => "" => "SELECT one, two, three FROM foo";

    ##
    my $DB = My::DB->new(...);
    my $row = $DB->foo;

    say $foo->one, $foo->three;

=head1 DESCRIPTION

Sometimes it's inconvenient to have to specify your column names in
advance. Perhaps you're running dynamic SQL with C<< DB->do_query >>,
perhaps you're using C<@ArgX> to allow unquoted interpolation, or
perhaps your database allows you to run stored procedures without
knowing the return type. In those cases you can use Row::Generic, which
uses the column names returned by the database.

If you use this class, you need to be careful to make your column names
unique. Most databases will quite happily return columns with duplicate
names; in this case which column is returned by the method with that
name is not well defined.

=cut

use warnings;
use strict;

use Carp ();

# set up ISA explicitly, since I don't want Irian to start trying to
# register this class against a DB
use parent "DBIx::Irian::Row";
use DBIx::Irian undef, qw"trace tracex";

# I'm seriously reconsidering the @{} overload...
no overloading;

=head1 METHODS

Row::Generic inherits from L<Row|DBIx::Irian::Row>, so it has the same
C<_DB> method and C<@{}> overload.

=head2 _new

    my $row = DBIx::Irian::Row::Generic->_new($DB, \@row, \@cols);

This takes the same arguments as L<< C<< Row->_new
>>|DBIx::Irian::Row/_new >>, but C<\@cols> is not optional.

=cut

sub _new {
    my ($class, $db, $row, $cols) = @_;
    tracex { 
        my $r = $row || ["???"];
        "VALUES [@$r]",
    } "ROW";
    my %cols = map +($$cols[$_] => $_), 0..$#$cols;
    bless [$db, $row, \%cols], $class;
}

=head2 AUTOLOAD

Row::Generic uses C<AUTOLOAD> to respond to all possible column names;
the autoloader then has to check the name requested against the list
supplied when the object was created. This is necessarily a good deal
slower than an ordinary Row class column method.

=cut

sub DESTROY { }

# Meh. Don't like this, but trying to get ->{UNIVERSAL,SUPER,Row}::can
# to give the right answers seems to be annoyingly difficult.
my %Methods = map +($_, 1), qw(
    _DB _new DESTROY AUTOLOAD
    isa can DOES VERSION
);

sub can {
    my ($self, $col) = @_;

    trace COL => "GENERIC CAN [$col]";

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
    trace COL => "GENERIC AUTOLOAD [$col] [$ix]";
    $self->[1][$ix];
}

1;

=head1 SEE ALSO

Row::Generic inherits from L<Row|DBIx::Irian::Row>.

=head1 COPYRIGHT

Copyright 2012 Ben Morrow.

Released under the 2-clause BSD licence.

