package DBIx::OQM::Util;

use warnings;
use strict;

use Sub::Name   qw/subname/;

use Exporter    qw/import/;

our @EXPORT_OK = qw( install_sub );

sub install_sub {
    my $pkg = @_ > 2 ? shift : caller;
    my ($n, $cv) = @_;
    no strict "refs";
    *{"$pkg\::$n"} = subname $n, $cv;
}

1;
