package DBIx::Irian::Query;

=head1 NAME

DBIx::Irian::Query - Deferred expansion for SQL statements

=head1 SYNOPSIS

    use DBIx::Irian "QuerySet", qw/expand_query/;

    my $q = "$Q{foo} $P{bar} $Arg[0]";
    my ($sql, @bind) = expand_query $q, { args => ["one"] };

    # $sql  = qq/"foo" ? ?/;
    # @bind = ("bar", "one");

=head1 DESCRIPTION

Query is the class implementing the magic variables you can use in
L<C<query>|DBIx::Irian::QuerySet/query> &c. Objects of class Query have
concat overloading, and Perl implements interpolation by converting it
into concatenation internally, so interpolating a Query into a string
will make that string, in turn, become a Query.

The purpose of this is to create (objects which look like) strings which
have sections that haven't been expanded yet, so they can be expanded
later once we know what values to use. They can also have sections which
expand to DBI placeholders, with a corresponding list of bind values.

Most of the implementation of this should be considered private, and
thus isn't documented. The main interface is through a number of
exported variables; see L<MAGIC VARIABLES|/MAGIC VARIABLES> below.

=head1 METHODS

Querys have no public methods, and there is no public constructor. Use
the variables.

=cut

use warnings;
use strict;

use Exporter        qw/import/;
use Scalar::Util    qw/reftype blessed/;
use List::Util      qw/reduce/;
use Sub::Name       qw/subname/;
use Carp;
use Tie::OneOff;

use DBIx::Irian       undef, qw/register_utils lookup trace tracex/;

# Only use Exporter for the variables. The functions are exported by
# Irian directly.
our @EXPORT = qw(
    %P %Q
    @Arg %Arg @ArgX %ArgX @ArgQ %ArgQ
    $Cols %Cols %Queries 
    %Self %SelfX %SelfQ
);

register_utils qw( djoin expand_query );

=head1 OVERLOADS

Querys overload the following operations:

=over 4

=item C<.> (concatenation)

The main purpose of this class is to have an overloaded C<.> operator.

=item C<""> (stringify)

Because there are situations where Perl insists on being able to
stringify a scalar, Querys have a stringify overload. Sections which
can't be expanded will be replaced with C<"%">.

=item C<bool>

Querys are always true in boolean context.

=back

=cut

use overload 
    q/./    => "concat",
    q/""/   => "force",
    bool    => sub { 1 },
    fallback => 1;

my $Defer   = "DBIx::Irian::Query";

push @Data::Dump::FILTERS, sub {
    $_[0]->class eq $Defer
        and return { dump => "SQL: [$_[1]]" };
    return;
};

=head1 UTILITIES

These are exported from L<Irian|DBIx::Irian>, but unlike sugar need to
be requested explicitly. See L<DBIx::Irian/Importing Irian>.

=cut

sub is_defer ($)    { blessed $_[0] and blessed $_[0] eq $Defer     }
sub is_cv ($)       { 
    ref $_[0] and not blessed $_[0] and reftype $_[0] eq "CODE"                 }

sub new {
    my ($class, $str, $val) = @_;
    !ref $str   or is_cv $str   or croak "I need a string or a coderef";
    @_ < 3      or is_cv $val   or croak "I need an unblessed coderef";
    bless [[$str], [@_ == 3 ? $val : ()]], $class;
}

sub defer (&$) { 
    $Defer->new(subname $_[1], $_[0]); 
}
sub placeholder (&$) {
    my ($cv, $n) = @_;
    $Defer->new("?", subname($n, $cv));
}

=head2 djoin

    my $x = djoin $y, @z;

Joins without forcing: that is, it joins a list of Querys and plain
strings while leaving the deferred sections deferred. Core C<join> would
stringify any Querys before joining, which would be unfortunate.

=cut

sub djoin {
    my ($j, @strs) = @_;
    reduce { "$a$j$b" } @strs;
}

sub force {
    my ($self) = @_;
    my ($sql, $bind) = @$self;
    join "", map ref $_ ? "%" : $_, @$sql;

    # We can't croak here, much as I'd like to, since a tied hash lookup
    # stringifies the key even though it then passes the original object
    # to FETCH. Grrrr.
    #@$bind          and croak "Query '$plain' has placeholders";
    #grep ref, @$sql and croak "Query '$plain' has deferred sections";
    #$plain;
}

sub concat {
    my ($left, $right, $reverse) = @_;

    length $right or return $left;

    my (@str, @val);
    ($str[0], $val[0]) = @$left;
    ($str[1], $val[1]) = 
        is_defer $right   ? @$right     :
        (["$right"], []);

    my @ord = $reverse ? (1, 0) : (0, 1);
    bless [[map @$_, @str[@ord]], [map @$_, @val[@ord]]], $Defer;
}

=head2 expand_query

    my ($sql, @bind) = expand_query $query, \%q;

Expand the deferred sections of a Query, returning the expanded string
and a list of bind values for any placeholders. C<%q> supplies the
values used for expansion; recognised keys are:

=over 4

=item args

An arrayref used to expand L<C<@Arg>|/@Arg> and friends.

=item self

A reference to an object used to expand L<C<%Self>|/%Self> and friends.

=item dbh

A L<DBI> database handle, used to expand L<C<%Q>|/%Q>. Defaults to
C<< $q{db}->dbh >>.

=item db

The L<DB|DBIx::Irian::DB> on behalf of which this expansion is being
performed.

=item row

A L<Row|DBIx::Irian::Row> class name, used to expand L<C<$Cols>|/$Cols>
and L<C<%Cols>|/%Cols>.

=back

If you don't think a particular Query uses a given variable, you can
omit its key; if you were wrong you'll get an error. Make sure you don't
supply any keys not on this list: it may cause unexpected behaviour.

If C<$query> is not a Query, stringify it.

=cut

sub expand_query {
    my ($query, $args) = @_;

    my ($sql, @bind) = is_defer $query 
        ? $query->expand($args)
        : "$query";

    wantarray or return $sql;
    return $sql, @bind;
}

# XXX this is almost but not quite the same as expand_query
sub qex { is_defer $_[0] ? $_[0]->expand($_[1]) : $_[0] }

sub undefer {
    my ($d, $q) = @_;
    #no overloading;
    is_cv $d        and $d = $d->($q);
    #no warnings "uninitialized";
    #trace EXP => "UNDEFER [$_[0]] -> [$d]";
    $d;
}

sub expand {
    my ($self, $q) = @_;

    tracex {
        @{$self->[0]} < 2 and return;
        "[$self]";
    } "EXP";
    my $sql = djoin "", map undefer($_, $q), @{ $self->[0] };
#    tracex {
#        no overloading;
#        "-> [$sql]";
#    } "EXP";

    if (defined $sql and not is_defer $sql) { 
        s/^\s+//, s/\s+$// for $sql;
    }

    wantarray or return $sql;
    my @bind = map $_->($q), @{ $self->[1] };
    return $sql, @bind;
}

sub cant {
    my ($what) = @_;
    my $n = (caller 2)[3];
    $n =~ s/.*:://;
    croak "can't use $n without a $what";
}

sub qid {
    my ($q, @id) = @_;
    $q->{db} or cant "db";
    $q->{dbh} ||= $q->{db}->dbh;
    $q->{dbh}->quote_identifier(@id);
}

sub reg {
    my ($q) = @_;
    $q->{reg} ||= do {
        my $r = $q->{row} or cant "row";
        lookup $r;
    };
}

# XXX This all needs tidying up. There is a huge amount of duplication,
# not to mention the whole thing being pretty unreadable.

=head1 MAGIC VARIABLES

These variables are all exported by Query, and also by Irian. They are
all tied, and return Querys of various kinds.

In the descriptions below, C<%q> is the hash passed to
L<C<expand_query>|/expand_query>.

=head2 C<%Q>

Returns the key as an SQL identifier, properly quoted for the database
you are using. If the key is a Query it will be expanded.

=cut

our %Q;
tie %Q, "Tie::OneOff", sub {
    my ($k) = @_;
    defer {
        my ($q) = @_;
        my $id = qex $k, $q;
        qid $q, $id;
    } '%Q';
};

=head2 C<%P>

Returns a placeholder (C<"?">) in the main string, but saves the key to
return as a bind value. If the key is a Query it will be expanded.

=cut

tie our %P, "Tie::OneOff", sub {
    my ($k) = @_;
    placeholder { qex $k, $_[0] } '%P';
};

=head2 C<@ArgX>

Returns the corresponding value from L<C<$q{args}>|/args>. Note that you
cannot perform further dereferences on that value, since they will not
be deferred; that is,

    $ArgX[0]{foo}
    $ArgX[0]->method()

will not do what you expect.

You should normally use L<C<@Arg>|/@Arg> instead, since this is
unquoted. If the index is a Query, it will B<not> be expanded. If the
argument in question is a Query, it will.

=cut

tie our @ArgX, "Tie::OneOff",
    FETCH => sub {
        my ($k) = @_;
        defer { qex $_[0]{args}[$k], $_[0] } '@ArgX';
    },
    FETCHSIZE => sub { undef };

=head2 C<%ArgX>

Assumes that L<C<$q{args}>|/args> is a list of (key => value) pairs, and
returns the value for the corresponding key.

You should normally use L<C<%Arg>|/%Arg> instead, since this is
unquoted. If the key is a Query, it will B<not> be expanded. If the
result is a Query, it will.

=cut

tie our %ArgX, "Tie::OneOff", sub {
    my ($k) = @_;
    defer {
        my $hv = $_[0]{arghv} ||= { @{$_[0]{args}} };
        qex $hv->{$k}, $_[0];
    } '%ArgX';
};

=head2 C<@Arg>

=head2 C<%Arg>

C<$Arg[$n]> is equivalent to C<< $P{ $ArgX[$n] } >>: that is, it takes
the requested argument out of L<C<$q{args}>|/args> and binds it to a
placeholder. Correspondingly for C<%Arg>.

=cut

tie our @Arg, "Tie::OneOff",
    FETCH => subname('@Arg', sub { $P{ $ArgX[$_[0]] } }),
    FETCHSIZE => sub { 0 };
tie our %Arg, "Tie::OneOff",
    subname '%Arg', sub { $P{ $ArgX{$_[0]} } };

=head2 C<@ArgQ>

=head2 C<%ArgQ>

C<$ArgQ[$n]> is equivalent to C<< $Q{ $ArgX[$n] } >>: that is, it takes
the requested argument out of L<C<$q{args}>|/args> and quotes it as an
SQL identifier. Correspondingly for C<%ArgQ>.

=cut

tie our @ArgQ, "Tie::OneOff",
    FETCH => subname('@ArgQ', sub { $Q{ $ArgX[$_[0]] } }),
    FETCHSIZE => sub { 0 };
tie our %ArgQ, "Tie::OneOff", 
    subname '%ArgQ', sub { $Q{ $ArgX{$_[0]} } };

=head2 C<$Cols>

Retrieves the list of column names for L<C<$q{row}>|/row>, quotes each
name as an SQL identifier, and joins them with C<", ">.

=cut

our $Cols = defer { 
    my ($q) = @_;
    join ", ", map qid($q, $_), @{reg($q)->{cols}};
} '$Cols';

=head2 C<%Cols>

As C<$Cols>, except the column names are qualified using the given key
as a table name. Note that this functionality (a call to L<< C<<
$q{dbh}->quote_identifier >>|DBI/quote_identifier >> with two
arguments) is not available through C<%Q>.

=cut

tie our %Cols, "Tie::OneOff", sub {
    my ($k) = @_;
    defer {
        my ($q) = @_;
        join ", ", map qid($q, $k, $_), @{reg($q)->{cols}};
    } '%Cols';
};

=head2 C<%Queries>

Returns the SQL used to define the given method in the calling class.
This method must have been created with
L<C<query>|DBIx::Irian::QuerySet/query>,
L<C<cursor>|DBIx::Irian::QuerySet/cursor>,
L<C<detail>|DBIx::Irian::QuerySet/detail> or
L<C<action>|DBIx::Irian::QuerySet/action>.

=cut

# This doesn't defer, it just returns an already-deferred result. This
# means the query in question needs to already be defined.
tie our %Queries, "Tie::OneOff", sub {
    my ($k) = @_;
    my $class = caller;
    my $reg = lookup +$class or croak "$class is not registered";
    $reg->{qs}{$k} or croak "$class has no query '$k'";
};

=head2 C<%SelfX>

Considers its key to be a method name, and calls that method (with no
arguments) on L<C<$q{self}>|/self>. If the key is a Query, it will
B<not> be expanded. If the return value of the method is a Query, it
will.

You should normally use C<%Self> instead, since this is unquoted.

=cut

tie our %SelfX, "Tie::OneOff", sub {
    my ($k) = @_;
    trace QRY => "SELF: [" . overload::StrVal($k) . "]";
    defer { qex $_[0]{self}->$k, $_[0] } '%SelfX';
};

=head2 C<%Self>

=head2 C<%SelfQ>

C<$Self{foo}> and C<$SelfQ{foo}> are equivalent to S<< C<< $P{
$SelfX{foo} } >> >> and S<< C<< $Q{ $SelfX{foo} } >> >> respectively.
They take the return value of a method and bind it to a placeholder or
quote it as an identifier.

=cut

tie our %Self, "Tie::OneOff", 
    subname '%Self', sub { $P{ $SelfX{$_[0]} } };
tie our %SelfQ, "Tie::OneOff",
    subname '%SelfQ', sub { $Q{ $SelfX{$_[0]} } };

1;

=head1 SEE ALSO

See L<Irian|DBIx::Irian> for bug reporting and general information.

=head1 BUGS

The internals are currently a bit of a mess. Fixing this B<shouldn't>
end up leaking out into the interface, but it might.

It should be possible to perform a partial expansion, only providing
some of the required information;
L<C<method>|DBIx::Irian::QuerySet/method> needs this to be able to
'close over' its arguments.

It is a little random when Querys will be expanded and when they will
not. Ideally they would always be expanded, but this seems to be a
little tricky to get right.

=head1 COPYRIGHT

Copyright 2012 Ben Morrow.

Released under the 2-clause BSD licence.

