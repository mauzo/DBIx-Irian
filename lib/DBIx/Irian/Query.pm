package DBIx::Irian::Query;

use warnings;
use strict;

use Exporter        qw/import/;
use Scalar::Util    qw/reftype blessed/;
use Sub::Name       qw/subname/;
use Carp;
use Tie::OneOff;

use DBIx::Irian       undef, qw/lookup/;

our @EXPORT = qw(
    @Arg %Arg @ArgX %ArgX %Q %P $Cols %Cols %Queries %Self %SelfX
);

use overload 
    q/./    => "concat",
    q/""/   => "force",
    bool    => sub { 1 },
    fallback => 1;

sub new {
    my ($class, $str, $val) = @_;
    not ref $str or reftype $str eq "CODE" and not blessed $str
        or croak "I need a string or a coderef";
    @_ < 3 or reftype $val eq "CODE" and not blessed $val
        or croak "I need an unblessed coderef";
    bless [[$str], [@_ == 3 ? $val : ()]], $class;
}

sub defer (&$)       { __PACKAGE__->new(subname $_[1], $_[0]) }
sub placeholder (&$) { __PACKAGE__->new("?", subname $_[1], $_[0]) }

sub force {
    my ($self) = @_;
    my ($sql, $bind) = @$self;
    my $plain = join "", map ref $_ ? "!" : $_, @$sql;
    # We can't croak here, much as I'd like to, since a tied hash lookup
    # stringifies the key even though it then passes the original object
    # to FETCH. Grrrr.
    #@$bind          and croak "Query '$plain' has placeholders";
    #grep ref, @$sql and croak "Query '$plain' has deferred sections";
    $plain;
}

sub concat {
    my ($left, $right, $reverse) = @_;
    my (@str, @val);
    ($str[0], $val[0]) = @$left;
    ($str[1], $val[1]) = eval { $right->isa(__PACKAGE__) }
        ? @$right : (["$right"], []);
    my @ord = $reverse ? (1, 0) : (0, 1);
    bless [[map @$_, @str[@ord]], [map @$_, @val[@ord]]], blessed $left;
}

sub expand {
    my ($self, %q) = @_;

    my $sql = join "",
        map ref $_ ? $self->$_(\%q) : $_,
        @{ $self->[0] };
    s/^\s+//, s/\s+$// for $sql;

    my @bind = map $self->$_(\%q),
        @{ $self->[1] };

    return $sql, @bind;
}

# XXX This all needs tidying up. There is a huge amount of duplication,
# not to mention the whole thing being pretty unreadable.

tie our @Arg, "Tie::OneOff",
    FETCH => sub { 
        my ($k) = @_; 
        placeholder { $_[1]{args}[$k] } '@Arg'; 
    },
    FETCHSIZE => sub { undef };
tie our %Arg, "Tie::OneOff", sub {
    my ($k) = @_;
    placeholder { 
        my $hv = $_[1]{arghv} ||= { @{$_[1]{args}} };
        $hv->{$k};
    } '%Arg';
};

# Unquoted versions
tie our @ArgX, "Tie::OneOff",
    FETCH => sub {
        my ($k) = @_;
        defer { $_[1]{args}[$k] } '@ArgX';
    },
    FETCHSIZE => sub { undef };
tie our %ArgX, "Tie::OneOff", sub {
    my ($k) = @_;
    defer {
        my $hv = $_[1]{arghv} ||= { @{$_[1]{args}} };
        $hv->{$k};
    } '%ArgX';
};

tie our %Q, "Tie::OneOff", sub {
    my ($k) = @_;
    defer { 
        $_[1]{dbh} ||= $_[1]{self}->_DB->dbh;
        $_[1]{dbh}->quote_identifier($k) 
    } '%Q';
};
tie our %P, "Tie::OneOff", sub {
    my ($k) = @_;
    placeholder { $k } '%P';
};

our $Cols = defer { 
    $_[1]{dbh} ||= $_[1]{self}->_DB->dbh;
    join ", ", 
        map $_[1]{dbh}->quote_identifier($_), 
        @{$_[1]{row}{cols}};
} '$Cols';
tie our %Cols, "Tie::OneOff", sub {
    my ($k) = @_;
    defer {
        $_[1]{dbh} ||= $_[1]{self}->_DB->dbh;
        join ", ",
            map $_[1]{dbh}->quote_identifier($k, $_),
            @{$_[1]{row}{cols}};
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

tie our %Self, "Tie::OneOff", sub {
    my ($k) = @_;
    warn "SELF: [" . overload::StrVal($k) . "]\n";
    placeholder { $_[1]{self}->$k } '%Self';
};

# Unquoted
tie our %SelfX, "Tie::OneOff", sub {
    my ($k) = @_;
    warn "SELFX: [" . overload::StrVal($k) . "]\n";
    defer { $_[1]{self}->$k } '%SelfX';
};

1;
