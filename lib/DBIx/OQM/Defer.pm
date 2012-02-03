package DBIx::OQM::Defer;

use warnings;
use strict;

use Scalar::Util    qw/blessed reftype/;
use Carp;   
use Exporter        qw/import/;

our @EXPORT = qw/defer placeholder/;

use overload
    q/./    => "concat",
    q/""/   => "force";

sub new {
    my ($class, $str, $val) = @_;
    not ref $str or reftype $str eq "CODE" and not blessed $str
        or croak "I need a string or a coderef";
    @_ < 3 or reftype $val eq "CODE" and not blessed $val
        or croak "I need an unblessed coderef";
    bless [[$str], [@_ == 3 ? $val : ()]], $class;
}

sub defer (&)       { __PACKAGE__->new($_[0]) }
sub placeholder (&) { __PACKAGE__->new("?", $_[0]) }

sub concat {
    my ($left, $right, $reverse) = @_;
    my (@str, @val);
    ($str[0], $val[0]) = @$left;
    ($str[1], $val[1]) = eval { $right->isa(__PACKAGE__) }
        ? @$right : (["$right"], []);
    my @ord = $reverse ? (1, 0) : (0, 1);
    bless [[map @$_, @str[@ord]], [map @$_, @val[@ord]]], blessed $left;
}

sub force { join "", map ref $_ ? $_->() : $_, @{$_[0][0]} }
sub bind { map $_->(), @{$_[0][1]} }

1;
