package t::Util;

use warnings;
use strict;

require Exporter;
our @EXPORT = qw/fakerequire/;

require Test::More;
require Test::Exports;

sub import {
    my $pkg = caller;
    strict->import;
    warnings->import;
    t::Util->Exporter::export($pkg);
    Test::More->Exporter::export($pkg);
    Test::Exports->Exporter::export($pkg);
}

sub fakerequire {
    my ($name, $code) = @_;
    
    local @INC = (sub {
        if ($_[1] eq $name) {
            open my $CODE, "<", \$code;
            return $CODE;
        }
        return;
    }, @INC);

    package main;
    delete $INC{$name};
    require $name;
}

1;
