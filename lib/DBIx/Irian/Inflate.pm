package DBIx::Irian::Inflate;

use warnings;
use strict;

use Carp;
use Scalar::Util    qw/blessed reftype/;

our @EXPORT = "register_inflators";

my %Inflators;

sub lookup { $Inflators{$_[1]} }

sub register {
    my ($self, $name, $cv) = @_;
    $Inflators{$name} and croak 
        "Inflator '$name' already registered";
    ref $cv and not blessed $cv and reftype $cv eq "CODE"
        or croak "Inflators must be unblessed coderefs";
    $Inflators{$name} = $cv;
}

sub register_inflators {
    while (my ($n, $cv) = splice @_, 0, 2) {
        __PACKAGE__->register($n, $cv);
    }
}

register_inflators(
    ISBN    => sub { 
        require Business::ISBN;
        Business::ISBN->new($_[0]); 
    },
);

1;