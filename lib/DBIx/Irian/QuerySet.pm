package DBIx::Irian::QuerySet;

=head1 NAME

DBIx::Irian::QuerySet - Objects which know how to make queries

=head1 SYNOPSIS

    package My::DB::QS::Book;
    use DBIx::Irian "QuerySet";

    setup_row_class Book => qw/id isbn title/;

    query by_isbn => Book =>
        "SELECT $Cols FROM book WHERE isbn = $Arg[0]";

    cursor all => Book =>
        "SELECT $Cols FROM book ORDER BY isbn";

    detail count =>
        "SELECT count(*) FROM book";

    action add => <<SQL;
        INSERT INTO book (isbn, title)
        VALUES ($Arg{isbn}, $Arg{title})
    SQL

=head1 DESCRIPTION

QuerySet is the base class of L<DB|DBIx::Irian::DB> and
L<Row|DBIx::Irian::Row>, and also a concrete class in its own right. A
QuerySet holds a reference to a DB, and knows how to use that DB to make
queries on the database it is connected to.

You must set up inheritance from QuerySet via DBIx::Irian: see
L<DBIx::Irian/Importing Irian>.

QuerySet itself only provides two methods, and they are both
underscore-prefixed to stop them from interfering with your own methods.
It also provides a number of 'sugar subs' (see L<DBIx::Irian/Sugar>)
which allow you to build methods for making queries.

=cut

use warnings;
use strict;

use DBIx::Irian           undef, qw(
    trace tracex 
    install_sub lookup load_class load_module 
    expand_query
);
use DBIx::Irian::Cursor;

use Carp;
use Scalar::Util qw/reftype blessed/;

BEGIN { our @CLEAN = qw( 
    carp croak reftype blessed
    register_query install_db_method build_query build_row_query
) }

=head1 METHODS

=head2 _new

    my $qs = My::QS->_new($DB);

This is the constructor, a class method. C<$DB> is the
L<DB|DBIx::Irian::DB> object this QuerySet is associated with.

Normally you would not call this, but let the L<C<queryset>|/queryset>
sugar handle it for you.

=cut

sub _new { 
    my ($class, $db) = @_;
    bless \$db, $class;
}

=head2 _DB

    my $DB = $qs->_DB;

Returns the L<DB|DBIx::Irian::DB> we were passed on construction.

=cut

sub _DB { ${$_[0]} }

sub register_query {
    my ($pkg, $name, $query) = @_;

    my $reg = lookup $pkg or croak "$pkg is not registered";
    $reg->{qs}{$name} and croak 
        "$pkg already has a query called '$name'";
    $reg->{qs}{$name} = $query;

    trace QRY => "QUERY [$pkg][$name]: [$query]";
}

sub install_db_method {
    my ($pkg, $name, $method, $args) = @_;

    trace QRY => "DB METHOD [$pkg][$name]: [$method]";

    install_sub $pkg, $name, sub {
        my ($self, @args) = @_;
    
        trace QRY => "CALL [$method] [$pkg][$name]";

        my $DB = $self->_DB;
        $DB->$method(@$args, { 
            self    => $self,
            args    => \@args,
        });
    };
}

sub build_query {
    my ($method) = @_;
    sub {
        my ($name, $query) = @_;
        my $pkg = caller;

        register_query $pkg, $name, $query;
        install_db_method $pkg, $name, $method, [$query];
    };
}

sub build_row_query {
    my ($method) = @_;
    sub {
        my ($name, $row, $query) = @_;
        my $pkg = caller;

        my $class = $row
            ? load_class($pkg, $row, "Row")
            : load_module("DBIx::Irian::Row::Generic");

        register_query $pkg, $name, $query;
        install_db_method $pkg, $name, $method, [$class, $query];

        trace QRY => "ROW [$pkg][$name]: [$class]";
    };
}

=head1 SUGAR

These sugar subs will be imported into your namespace by

    use DBIx::Irian "QuerySet";

and removed at the end of compiling the enclosing scope. See
L<DBIx::Irian/Importing Irian>.

=for comment
Pod can only appear between statements, so all the sugars need to be
documented here.

=head2 method

    method $name, sub {...};
    method $name, $string;

Creates a method with the given C<$name>. If a string is provided the
method will always return that string.

B<XXX>: At some point in the future I hope to change this so that if
C<$string> is a L<Query|DBIx::Irian::Query> the method created will
expand C<%ArgX> and C<%SelfX> before returning it, effectively closing
over the current method parameters.

=head2 queryset

    queryset $name, $class;

Install a method C<$name> which returns an object of class C<$class>,
linked to the same DB as the object it was called on. C<$class> is
qualified by passing it through L<load_class|DBIx::Irian/load_class>
with a type of C<"QuerySet">.

=head2 query

    query $name, $row, $query;

Creates a method called C<$name> which runs C<$query>, packing the
results up into objects of class C<$row>. C<$row> is qualified by
passing it through L<load_class|DBIx::Irian/load_class> with a type of
C<"Row">, and so should inherit from L<Row|DBIx::Irian::Row>.

In scalar context, the generated method will return one row (as an
object), and warn if the query returned more than one. In list context
all the rows returned will be fetched and the packed-up objects returned
as a list, so don't use this for queries which will return huge numbers
of rows.

If C<$row> is the empty string, this will use
L<Row::Generic|DBIx::Irian::Row::Generic> as the row class. This is a
special row class which uses the column names returned by the database.

=head2 cursor

    cursor $name, $row, $query;

Creates a method C<$name> which runs C<$query>, but instead of returning
the results immediately it returns a L<Cursor|DBIx::Irian::Cursor> which
can be used to retrieve them. The Cursor will be set up to use C<$row>
as its row class; C<$row> is qualified as for L<query|/query>.

Currently Row::Generic cannot be used with C<cursor>.

=head2 detail

    detail $name, $query;

Create a method C<$name> which runs C<$query>, which is expected to
return a single column. In scalar context the generated method will
return the value from the first row, and warn if the query returned more
than one. In list context it will return a list of all the values
returned.

=head2 action

    action $name, $query;

Create a method C<$name> which runs C<$query>, which should not return
any rows. This is what you should use for DML queries like C<INSERT>,
C<UPDATE> and C<DELETE>. Returns the number of rows affected, or
C<"0E0"> if none were.

=head2 row_class

    my $class = row_class($row);

Qualifies C<$row> wrt the current DB, loads that class, and returns the
full class name. This is just a convenient wrapper around 

    load_class(__PACKAGE__, $row, "Row")

see L<DBIx::Irian/load_class>.

B<XXX>: This is currently classified as 'sugar', rather than 'utility',
so it doesn't need explicitly importing from Irian. This may change in
the future.

=head2 setup_row_class

    setup_row_class $class, @fields;

Creates a Row class with the given C<@fields>, without needing to create
a whole module file. C<$class> will be qualified against the current DB
as usual, and the generated module will look something like this:

    package My::DB::Book;
    use DBIx::Irian "Row";
    columns "id", "isbn", "title";
    1;

Returns the full class name of the generated class.

B<XXX>: As L<row_class|/row_class> above.

=cut

our %SUGAR = (
    # XXX these shouldn't really be here
    row_class => sub { 
        load_class scalar caller, $_[0], "Row" 
    },

    setup_row_class => sub {
        my ($row, @cols) = @_;
        my $pkg = caller;
        my $qcol = join ", ", map qq!"\Q$_\E"!, @cols;

        tracex { "[$row] [@cols]" } "GEN";

        # Make sure these are preloaded
        require PerlIO::scalar;
        require DBIx::Irian::Row;

        local @INC = sub {
            my ($self, $mod) = @_;
            trace GEN => "REQUIRE: [$mod]";
            s!/!::!g, s/\.pm$// for $mod;
            my $code = <<MOD;
package $mod;
use DBIx::Irian "Row";
columns $qcol;
1;
MOD

            trace GEN => "MOD: [$code]";
            open my $MOD, "<", \$code;
            return $MOD;
        };

        load_class $pkg, $row, "Row";
    },

    method => sub {
        my ($name, $meth) = @_;
        my $pkg = caller;
        
        trace QRY => "METHOD [$pkg][$name]: [$meth]";
        install_sub $pkg, $name,
            ref $meth && !blessed $meth && reftype $meth eq "CODE"
                ? $meth
                : sub { $meth };
    },

    queryset => sub {
        my ($name, $qs) = @_;
        my $pkg = caller;
        my $class = load_class $pkg, $qs, "QuerySet";
        trace QRY => "QUERYSET [$pkg][$name]: [$class]";
        install_sub $pkg, $name, sub {
            $class->_new($_[0]->_DB)
        };
    },

    query   => build_row_query("do_query"),
    cursor  => build_row_query("do_cursor"),
    detail  => build_query("do_detail"),
    action  => build_query("do_action"),
);

1;

=head1 SEE ALSO

See L<DBIx::Irian> for bug reporting and other general information.

L<DB|DBIx::Irian::DB> and L<Row|DBIx::Irian::Row> are subclasses of
QuerySet, and so have the same sugar available to them.

=head1 COPYRIGHT

Copyright 2012 Ben Morrow.

Released under the 2-clause BSD licence.

