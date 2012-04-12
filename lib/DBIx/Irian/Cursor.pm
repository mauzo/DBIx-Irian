package DBIx::Irian::Cursor;

=head1 NAME

DBIx::Irian::Cursor - Cursor support for Irian

=head1 SYNOPSIS

    my $curs = DBIx::Irian::Cursor->new(
        DB      => $DB,
        sql     => "SELECT foo",
        bind    => [],
        row     => "My::DB::Row",
    );

    my $row = $curs->next;
    $row    = $curs->peek;

    my @rows = $curs->all;

    while (my $row = <$curs>) {...}

=head1 DESCRIPTION

Cursor is the class which manages Irian cursors, such as are returned by
L<C<cursor>|DBIx::Irian::QuerySet/cursor> methods. A Cursor object holds
the data it needs to manipulate the cursor on the database, and knows
which L<Row|DBIx::Irian::Row> class its results should be blessed into.

True server-side cursors require support from the
L<Driver|DBIx::Irian::Driver>, since DBI doesn't provide direct support
for cursors. Databases which don't have explicit Driver support get a
generic implementation, which fetches all the data into Perl data
structures and emulates the cursor from there. While this should provide
correct behaviour, it will be less efficient than not using a Cursor in
the first place.

=cut

use warnings;
use strict;

use Carp;
use DBIx::Irian   undef, qw/install_sub trace/;

=head1 METHODS

=head2 new

    my $curs = DBIx::Irian::Cursor->new(%args);

Construct a Cursor object (this is a class method). C<%args> should be a
list of (key => value) pairs; recognised keys are

=over 4

=item DB

The L<DB|DBIx::Irian::DB> this cursor is being constructed for.

=item sql

The SQL statement this cursor is to execute. Note that this must be a
plain string, not a L<Query|DBIx::Irian::Query>.

=item bind

An arrayref of bind values corresponding to the placeholders in
C<$args{sql}>.

=item row

The subclass of L<Row|DBIx::Irian::Row> to use when returning the
results.

=item batch

The number of rows to retrieve at a time. Cursor fetches are batched,
for efficiency, and this allows you to choose the size of the batches.
Defaults to 20, for no terribly good reason. Note that since
L<C<cursor>|DBIx::Irian::QuerySet/cursor> currently gives you no way to
set this, it's a lot less useful than it might be.

=back

Do not provide any other keys: this may produce unexpected results.

=cut

sub new {
    my ($class, %attr) = @_;
    my $self = bless \%attr, $class;
    $self->{cursor} = $self->DB->driver->cursor(
        $self->sql, $self->bind
    );
    $self->{rows} = [];
    $self->{batch} ||= 20;
    $self;
}

=head2 DB

=head2 sql

=head2 bind

=head2 row

=head2 batch

Accessors for the values provided to L<< C<< ->new >>|/new >>. Note
that these are read-only.

=head2 cursor

This returns driver-specific information about the server-side cursor in
use, if any. See the documentation for the L<Driver|DBIx::Irian::Driver>
you are using to see what you can do with it.

=cut

for my $n (qw/DB sql bind row cursor batch/) {
    install_sub $n, sub { $_[0]{$n} };
}

sub _rows {
    my ($self) = @_;
    # $rs is undef after the cursor is exhausted
    my $rs = $self->{rows} or return;
    @$rs or $rs = $self->{rows} = 
        $self->DB->driver->fetch($self->cursor, $self->batch)
        or return;
    trace CUR => "FETCHED [" . scalar @$rs . "]";
    return $rs;
}

=head2 next

Returns the next row from the cursor, and advances the cursor pointer.
Returns the empty list if the cursor is exhausted.

=cut

sub next {
    my ($self) = @_;
    trace CUR => "NEXT [$$self{cursor}]";
    my $rs = $self->_rows or return;
    $self->row->_new($self->DB, shift @$rs);
}

=head2 peek

Returns the next row from the cursor without advancing the cursor
pointer. Note that this is done using the Perl-side buffer, so the
database doesn't need to support C<FETCH 0 FROM> or any equivalent.

=cut

sub peek {
    my ($self) = @_;
    my $rs = $self->_rows or return;
    $self->row->_new($self->DB, @$rs);
}

=head2 all

Retrieves and returns all the remaining rows from the cursor. After this
C<< ->next >> will return the empty list.

=cut

sub all {
    my ($self) = @_;
    my ($db, $row, $curs, $n) = map $self->$_, 
        qw/DB row cursor batch/;

    my @rv  = map $row->_new($db, $_), @{delete $self->{rows}};

    # I realise we're necessarily eating memory at this point, but try
    # to avoid doing so more than we have to.
    while (my $rs = $db->driver->fetch($curs, $n)) {
        push @rv, map $row->_new($db, $_), @$rs;
    }

    return @rv;
}

=head2 DESTROY

Destroying the Cursor object will close the server-side cursor, so make
sure you don't keep an object hanging around longer than you need to.

=cut

sub DESTROY {
    my ($self) = @_;
    my $c = $self->cursor;
    $c and $self->DB->driver->close($c);
}

=head1 OVERLOADS

Since this is an iterator object, it overloads C<< <> >> to call the C<<
->next >> method. This means you can iterate over a Cursor like this

    while (my $row = <$curs>) {
        ...
    }

=cut

use overload
    q/<>/   => "next",
    fallback => 1;

1;

=head1 BUGS

True cursors are only supported on databases with
L<Driver|DBIx::Irian::Driver> support; currently this is just Postgres.

It would be useful to support more operations on the cursor than just
'next'.

=head1 SEE ALSO

See L<DBIx::Irian|DBIx::Irian> for bug reporting and general
information.

See L<Driver|DBIx::Irian::Driver> and its database-specific subclasses
for information about cursor support on your particular database.

=head1 COPYRIGHT

Copyright 2012 Ben Morrow.

Released under the 2-clause BSD licence.

