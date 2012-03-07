package t::Util;

use warnings;
use strict;

require Exporter;
our @EXPORT = qw/
    fakerequire $Defer check_defer
/;

use Test::More;
use Test::Exports;

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

our $Defer = "DBIx::Irian::Query";

sub check_defer {
    my ($q, $str, $args, $exp, $name) = @_;
    isa_ok $q, $Defer,          $name;
    is $q->force, $str,         "$name forces OK";
    is "$q", $str,              "$name stringifies OK";
    is_deeply [$q->expand($args)], $exp,
                                "$name expands OK";
}

1;
