package DBIx::OQM::Query;

use warnings;
use strict;

use Exporter        qw/import/;
use Scalar::Util    qw/reftype blessed/;
use Sub::Name       qw/subname/;
use Carp;
use Tie::OneOff;

our @EXPORT = qw(
    @Arg %Arg @Cols $Cols %Cols %Self
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
    @$bind          and croak "Query '$plain' has placeholders";
    grep ref, @$sql and croak "Query '$plain' has deferred sections";
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

our $Cols = defer { 
    $_[1]{dbh} ||= $_[1]{self}->_DB->dbh;
    join ", ", 
        map $_[1]{dbh}->quote_identifier($_), 
        @{$_[1]{row}{cols}};
} '$Cols';
tie our @Cols, "Tie::OneOff",
    FETCH =>        sub { $_[1]{row}{cols}[$_[0]] },
    FETCHSIZE =>    sub { scalar @{$_[1]{row}{cols}} };
tie our %Cols, "Tie::OneOff", sub {
    my ($k) = @_;
    defer {
        $_[1]{dbh} ||= $_[1]{self}->_DB->dbh;
        join ", ",
            map $_[1]{dbh}->quote_identifier($k, $_),
            @{$_[1]{row}{cols}};
    } '%Cols';
};

tie our %Self, "Tie::OneOff", sub {
    my ($k) = @_;
    placeholder { $_[1]{self}->$k } '%Self';
};

1;
