package DBIx::Irian::Inflate;

=head1 NAME

DBIx::Irian::Inflate - Inflate Irian columns into objects

=head1 SYNOPSIS

    package My::DB::Book;
    use DBIx::Irian "Row";

    columns qw/id isbn title/;
    inflate isbn => "ISBN";

    ##
    my $b = find_a_Book();
    my $i = $b->isbn;
    die unless $i->isa("Business::ISBN");

=head1 DESCRIPTION

Database queries generally return plain data values. Usually they are
strings, sometimes they are more complicated than that; sometimes,
however, it would be convenient if they returned objects. Inflate
handles this for you, taking the string returned by the database and
using it to build an appropriate object.

Inflation is requested for a particular column of a particular row class
using the L<C<inflate>|DBIx::Irian::Row/inflate> sugar. The inflators
named must be registered with this class, for which you can use the
functions below.

B<XXX>: While C<inflate> should be considered stable, the rest of the
interface described here is likely to change. In particular, it seems
likely that some inflators will need more than just a subref.

=cut

use warnings;
use strict;

use Carp;
use Scalar::Util    qw/blessed reftype/;
use DBIx::Irian     undef, "register_utils";

register_utils "register_inflators";

my %Inflators;

=head1 METHODS

There are currently no object methods, and no constructors. Both methods
should be called on the class.

=head2 lookup

    my $sub = DBIx::Irian::Inflate->lookup($name);

Looks up a previously-registered inflator, returning its subref. If
C<$name> is C<undef>, returns C<undef>.

=cut

sub lookup { defined $_[1] ? $Inflators{$_[1]} : undef }

=head2 register

    DBIx::Irian::Inflate->register($name, sub {...});

Register an inflator, which can later be returned by C<lookup>. This
will throw an error if C<$name> is already registered.

The sub should accept an unblessed data value and return a blessed
object, or throw an exception. Returning an unblessed value will cause
problems, so don't do that.

=cut

sub register {
    my ($self, $name, $cv) = @_;
    $Inflators{$name} and croak 
        "Inflator '$name' already registered";
    ref $cv and not blessed $cv and reftype $cv eq "CODE"
        or croak "Inflators must be unblessed coderefs";
    $Inflators{$name} = $cv;
}

=head1 UTILITIES

These are exported from L<Irian|DBIx::Irian>, but unlike sugar need to
be requested explicitly. See L<DBIx::Irian/Importing Irian>.

=head2 register_inflators

    register_inflators %inf;

Registers a series of inflators, using C<< Inflate->register >>. C<%inf>
is a list of (name, subref) pairs.

=cut

sub register_inflators {
    while (my ($n, $cv) = splice @_, 0, 2) {
        __PACKAGE__->register($n, $cv);
    }
}

=head1 PROVIDED INFLATORS

=head2 ISBN

Expands an ISBN into a L<Business::ISBN>.

=cut

register_inflators(
    ISBN    => sub { 
        require Business::ISBN;
        Business::ISBN->new($_[0]); 
    },
);

1;

=head1 SEE ALSO

See L<Irian|DBIx::Irian> for bug reporting and general information.

Inflators are usually used via L<Row|DBIx::Irian::Row>.

=head1 BUGS

There is no deflator interface. This is because I can't see where it
would fit without ending up more awkward than manually extracting the
required value from the object.

I should probably support object-based inflators as well as
coderef-based.

=head1 COPYRIGHT

Copyright 2012 Ben Morrow.

Released under the 2-clause BSD licence.

