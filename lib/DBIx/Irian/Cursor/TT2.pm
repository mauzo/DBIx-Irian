package DBIx::Irian::Cursor::TT2;

=head1 NAME

DBIx::Irian::Cursor::TT2 - Wrap an Irian Cursor in a TT2 Iterator

=head1 SYNPOSIS

    my $cursor = ...; # a DBIx::Irian::Cursor
    my $it = DBIx::Irian::Cursor::TT2->new($cursor);
    # my $it = $cursor->tt2;

    $it->get_next();

    my $template = ...; # A Template object
    $template->process($input, {
        cursor  => $it,
    });

    ## in the template
    [% FOR r IN cursor %]
        ...
    [% END %]

=head1 DESCRIPTION

This class is a subclass of L<Template::Iterator> which wraps a
L<DBIx::Irian::Cursor|Cursor>. This means your templates don't need to
know whether they are passed an arrayref from a C<query> method or a
Cursor from a C<cursor> method.

=cut

use 5.010;
use warnings;
use strict;

use parent "Template::Iterator";

use DBIx::Irian         undef, qw/trace/;
use Template::Constants ":status";

=head1 METHODS

=head2 new

    $iterator = DBIx::Irian::Cursor::TT2->new($cursor);

=cut

sub new {
    my ($class, $curs) = @_;
    trace CUR => "NEW ITERATOR [$curs] [$class]";
    bless \$curs, $class;
}

=head2 get_first

=head2 get_next

    ($row, $status) = $iterator->get_next;

These both call the Cursor's L<< DBIx::Irian::Cursor/next|->next >>
method.

=cut

sub get_next { 
    my ($self) = @_;
    my ($row) = $$self->next
        or return (undef, STATUS_DONE);
    return $row;
}

*get_first = \&get_next;

=head2 get_all

    ($rows, $status) = $iterator->get_all;

This calls the Cursor's C<< DBIx::Irian::Cursor/all|->all >> method and
returns the result as an arrayref.

=cut

sub get_all {
    my ($self) = @_;
    my $rows = [$$self->all];
    return ($rows, STATUS_DONE);
}

=head2 next

    $row = $iterator->next;

This calls the Cursor's C<< DBIx::Irian::Cursor/peek|->peek >> method to
fetch the next row without advancing the cursor pointer.

=cut

sub next {
    my ($self) = @_;
    $$self->peek;
}

=head2 size

This calls C<< ->peek >> on the cursor, and returns "0E0" if there are
any rows left and undef if there aren't. This will at least allow tests
like

    [% IF cursor.size %]

to work properly.

=cut

sub size {
    my ($self) = @_;
    $$self->peek or return;
    return "0E0";
}

=head2 max

=head2 index

=head2 count

=head2 first

=head2 last

=head2 prev

=head2 parity

=head2 odd

=head2 even

These are currently not implemented, and return undef. All but C<max>
and C<count> could be implemented by counting rows client-side, if there
was a good reason to do so.

=cut

sub AUTOLOAD {
    our $AUTOLOAD; 
    trace CUR => "ITERATOR AUTOLOAD [$AUTOLOAD]";
    return;
}

1;

=head1 BUGS

Iterator methods other than 'next' are not implemented.

The C<get_first> method should probably rewind the cursor, but Driver
doesn't currently support that.

=head1 SEE ALSO

See L<DBIx::Irian|DBIx::Irian> for bug reporting and general
information.

=head1 COPYRIGHT

Copyright 2013 Ben Morrow.

Released under the 2-clause BSD licence.
