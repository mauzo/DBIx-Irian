package DBIx::Irian::Row;

=head1 NAME

DBIx::Irian::Row - Base class for Irian row classes

=head1 SYNOPSIS

    package My::DB::Book;
    use DBIx::Irian "Row";

    columns qw/id isbn title/;
    inflate isbn => ISBN;

    query authors => Author =>
        "SELECT $Cols FROM $Q{author} WHERE $Q{book} = $Self{id}";

    action set_title => <<SQL;
        UPDATE $Q{book} SET $Q{title} = $Arg[0]
        WHERE $Q{id} = $Self{id}
    SQL

    ##
    package My::DB::Book::OReilly;
    use DBIx::Irian "Row";

    extends "Book";
    columns qw/animal/;

=head1 DESCRIPTION

Row is the parent class of all Irian row classes. A Row represents a
single row returned by a database query: it has methods to extract the
returned columns, and methods to make further queries for related data.

Row inherits from L<QuerySet|DBIx::Irian::QuerySet>, so all the sugars
available for QuerySets are also available for Rows. Normally a query
based on a Row would want to use L<C<%Self>|DBIx::Irian::Query/%Self> to
find some set of related rows: see the examples in the
L<SYNOPSIS|/SYNOPSIS>.

Rows are, by design, immutable once created. The column methods are
read-only; to update the database you need to use an C<action> method or
otherwise explicitly run a DML query. Doing so will not update the
values in a previously-created Row: if you want an updated copy you will
need to re-run whatever query created it in the first place.

=cut

use warnings;
use strict;

use parent "DBIx::Irian::QuerySet";

use DBIx::Irian   undef, qw(
    trace tracex
    install_sub register lookup find_sym load_class qualify
);
use Carp            qw/croak/;
use Scalar::Util    qw"reftype blessed";

BEGIN { our @CLEAN = qw/croak reftype blessed/ }

no overloading;
use overload
    q/@{}/      => sub { $_[0][1] },
    fallback    => 1;

=head1 METHODS

Row provides the same two methods as QuerySet, both underscore-prefixed
so they don't get in the way of your column names. However, C<_new>
takes different arguments.

=head2 _new

    my $row = My::Row->_new($DB, \@values, \@names?);

Construct a new Row object: this is a class method. C<$DB> is the DB
this Row is attached to; C<@values> is the row of data retrieved from
the database. C<@names> is a list of the column names used by the
database: this is mostly for the benefit of
L<Row::Generic|DBIx::Irian::Row::Generic>, though all Row classes will
use it for tracing.

Normally you would not call this, but let one of the query methods
handle it for you.

=cut

sub _new {
    my ($class, $db, $row, $names) = @_;

    ref $row and reftype $row eq "ARRAY" or Carp::confess
        "Row is not an arrayref";

    if (my $inf = lookup $class, "inflate") {
        # copy, since peek might give us more than one Row for this
        # fetched row. Ideally that should be fixed...
        $row = [
            map $inf->[$_] ? $inf->[$_]->($row->[$_]) : $row->[$_],
                0..$#$row
        ];
    }

    tracex {
        my $r = $row || ["???"];
        "VALUES [@$r]",
    } "ROW";

    bless [$db, $row], $class;
}

=head2 _DB

    my $DB = $row->_DB;

Returns the L<DB|DBIx::Irian::DB> this Row was derived from.

=cut

sub _DB { $_[0][0] }

=head2 _COLUMNS

    my @cols = $row->_COLUMNS;

Returns a list of the column names for this Row. Except in the case of a
L<Row::Generic|DBIx::Irian::Row::Generic>, these will be the names
passed to L<C<columns>|/columns> rather than the names returned from the
database.

=cut

sub _COLUMNS {
    my ($self) = @_;
    
    my $class   = blessed $self
        or croak "DBIx::Irian::Row->_COLUMNS is an instance method";
    my $cols    = lookup $class, "cols"
        or croak "No columns registered for '$class'";

    @$cols;
}

=head1 OVERLOADS

=head2 C<@{}>

Classes derived from Row have an overloaded array-dereference (C<@{}>)
operator (see L<overload> for more information). This returns the
original arrayref of row data passed to C<_new>.

B<XXX>: I'm not clear yet what this should do in the presence of
inflators. Currently it returns the inflated values, but that may
change.

=head1 SUGAR

These sugar subs will be imported into your namespace by

    use DBIx::Irian "Row";

and removed at the end of compiling the enclosing scope. See
L<DBIx::Irian/Importing Irian>.

=over 4

=item method

=item query

=item cursor

=item detail

=item action

=item row_class

=item setup_row_class

These are all inherited from L<QuerySet|DBIx::Irian::QuerySet/SUGAR>.

=back

=head2 columns

    columns @cols;

Specifies the list of column names for this class. A method will be
generated for each column, returning the corresponding value out of the
arrayref passed to L<C<_new>|/_new>. You may only call C<columns> once
per class.

=head2 extends

    extends @parents;

Specifies that this Row class inherits from (an)other class(es). As well
as setting up Perl-level C<@ISA> inheritance, this will also inherit all
the columns of the parents, in order. If both C<extends> and C<columns>
are used, C<extends> must come first. You may only call C<extends> once
per class.

=head2 inflate

    inflate %cols;

Sets up inflators for the columns listed, which arrange for the value
returned from the database to be inflated into an object. C<%cols>
should be a list of (column name, inflator name) pairs; the inflators
will be looked up with L<< C<< Inflate->lookup
>>|DBIx::Irian::Inflate/lookup >>, which see.

=cut

our %SUGAR = (
    columns => sub {
        my @mycols = @_;
        my $pkg = caller;

        tracex { "COLUMNS [$pkg]: [@mycols]" } "COL";
        register $pkg, mycols => \@mycols;

        my $parents = lookup($pkg, "extends") || [];
        my @inherit = map @{ lookup($_, "cols") || [] }, @$parents;

        tracex { "INHERIT [$pkg] COLUMNS [@inherit]" } "COL";
        register $pkg, cols => [ @inherit, @_ ];

        my @inf;
        for (@$parents) {
            my $cols = lookup($_, "cols")       || [];
            my $inf  = lookup($_, "inflate")    || [];

            # make sure we get enough entries to cover all the columns
            push @inf, @$inf[0..$#$cols];
        }

        tracex { "INHERIT [$pkg] INFLATE [@inf]" } "COL";
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

        tracex { "EXTENDS: [$pkg] [@ext]" } "COL";

        my @ps = map load_class($pkg, $_, "Row"), @ext;
        register $pkg, extends => \@ps;

        tracex { "EXTENDS: [$pkg] [@ps]" } "COL";
    },

    inflate => sub {
        my (%inf) = @_;
        my $pkg = caller;

        tracex { 
            my @inf = map "$_|$inf{$_}", keys %inf;
            "INFLATE [$pkg]: [@inf]" 
        } "COL";

        my $mycols = lookup $pkg, "mycols" or Carp::croak 
            "'inflate' must come after 'columns'";
        
        my $inf = lookup $pkg, "inflate";
        $inf or register $pkg, inflate => ($inf = []);

        push @$inf, DBIx::Irian::Inflate->lookup($inf{$_})
            for @$mycols;
    },

);

1;

=head1 SEE ALSO

See L<DBIx::Irian> for bug reporting and other general information.

L<Row::Generic|DBIx::Irian::Row::Generic> is a subclass of Row that
extracts its column names from the rows returned by the database.

See L<DBIx::Irian::Inflate> for documentation of the inflation mechanism.

=head1 COPYRIGHT

Copyright 2012 Ben Morrow.

Released under the 2-clause BSD licence.

