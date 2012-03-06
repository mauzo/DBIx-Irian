package DBIx::Irian::Query;

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

sub expand_query {
    my ($query, $args) = @_;

    my ($sql, @bind) = is_defer $query 
        ? $query->expand($args)
        : $query;

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

# XXX This all needs tidying up. There is a huge amount of duplication,
# not to mention the whole thing being pretty unreadable.

our %Q;
tie %Q, "Tie::OneOff", sub {
    my ($k) = @_;
    defer {
        my ($q) = @_;
        my $id = qex $k, $q;

        # If we haven't got a DB yet, croak
        $q->{db} or croak "can't use %Q without a db";

        $q->{dbh} ||= $q->{db}->dbh;
        $q->{dbh}->quote_identifier($id) 
    } '%Q';
};
tie our %P, "Tie::OneOff", sub {
    my ($k) = @_;
    placeholder { qex $k, $_[0] } '%P';
};

tie our @ArgX, "Tie::OneOff",
    FETCH => sub {
        my ($k) = @_;
        defer { qex $_[0]{args}[$k], $_[0] } '@ArgX';
    },
    FETCHSIZE => sub { undef };
tie our %ArgX, "Tie::OneOff", sub {
    my ($k) = @_;
    defer {
        my $hv = $_[0]{arghv} ||= { @{$_[0]{args}} };
        qex $hv->{$k}, $_[0];
    } '%ArgX';
};

tie our @Arg, "Tie::OneOff",
    FETCH => subname('@Arg', sub { $P{ $ArgX[$_[0]] } }),
    FETCHSIZE => sub { undef };
tie our %Arg, "Tie::OneOff",
    subname '%Arg', sub { $P{ $ArgX[$_[0]] } };

tie our @ArgQ, "Tie::OneOff",
    FETCH => subname('@ArgQ', sub { $Q{ $ArgX[$_[0]] } }),
    FETCHSIZE => sub { undef };
tie our %ArgQ, "Tie::OneOff", 
    subname '%ArgQ', sub { $Q{ $ArgX{$_[0]} } };

our $Cols = defer { 
    $_[0]{dbh} ||= $_[0]{self}->_DB->dbh;
    join ", ", 
        map $_[0]{dbh}->quote_identifier($_), 
        @{$_[0]{row}{cols}};
} '$Cols';
tie our %Cols, "Tie::OneOff", sub {
    my ($k) = @_;
    defer {
        $_[0]{dbh} ||= $_[0]{self}->_DB->dbh;
        join ", ",
            map $_[0]{dbh}->quote_identifier($k, $_),
            @{$_[0]{row}{cols}};
    } '%Cols';
};

# This doesn't defer, it just returns an already-deferred result. This
# means the query in question needs to already be defined.
tie our %Queries, "Tie::OneOff", sub {
    my ($k) = @_;
    my $class = caller;
    my $reg = lookup +$class or croak "$class is not registered";
    $reg->{qs}{$k} or croak "$class has no query '$k'";
};

tie our %SelfX, "Tie::OneOff", sub {
    my ($k) = @_;
    trace QRY => "SELF: [" . overload::StrVal($k) . "]";
    defer { qex $_[0]{self}->$k, $_[0] } '%SelfX';
};
tie our %Self, "Tie::OneOff", 
    subname '%Self', sub { $P{ $SelfX{$_[0]} } };
tie our %SelfQ, "Tie::OneOff",
    subname '%SelfQ', sub { $Q{ $SelfX{$_[0]} } };

1;
