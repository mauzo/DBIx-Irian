package t::Util;

use 5.010;
use warnings;
use strict;

require Exporter;
our @EXPORT = qw/
    slurp fakerequire
    $Defer check_defer $DB $DBH 
    check_row register_mock_rows check_history
/;

use Test::More;
use Test::Exports;

require DBD::Mock;

sub import {
    my $pkg = caller;
    strict->import;
    warnings->import;
    t::Util->Exporter::export($pkg);
    Test::More->Exporter::export($pkg);
    Test::Exports->Exporter::export($pkg);
}

sub slurp {
    my ($file) = @_;
    open my $F, "<", $file or die "can't open '$file': $!";
    local $/;
    <$F>;
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

{   package t::FakeDBH;
    sub quote_identifier { @_ > 2 ? "QQ<$_[1]|$_[2]>" : "Q<$_[1]>" }
}
our $DBH = bless [], "t::FakeDBH";
*DBD::Mock::db::quote_identifier = \&t::FakeDBH::quote_identifier;

{   package t::FakeDB;
    sub dbh { $DBH }
}
our $DB = bless [], "t::FakeDB";

fakerequire "DBIx/Connector/Driver/Mock.pm", q{
    package DBIx::Connector::Driver::Mock;
    use parent "DBIx::Connector::Driver";

    sub savepoint   { $_[1]->do("SAVEPOINT $_[2]")      }
    sub release     { $_[1]->do("RELEASE $_[2]")        }
    sub rollback_to { $_[1]->do("ROLLBACK TO $_[2]")    }

    1;
};

sub check_row {
    my ($r, $row, $fld, $want, $name) = @_;

    isa_ok $r, $row,                    $name;
    isa_ok $r, "DBIx::Irian::Row",      $name;

    my $got = [map eval { $r->$_ }, @$fld];
    is_deeply $got, $want,              "$name returns correct row";
}

sub register_mock_rows {
    my ($db, $prefix, @rows) = @_;
    my $dbh = $db->dbh;
    for (@rows) {
        my ($sql, @rows) = @$_;
        $dbh->{mock_add_resultset} = {
            sql     => "$prefix $sql",
            results => \@rows,
        };
        #diag "MOCK [$prefix $sql]";
    }
}

sub check_history {
    my ($dbh, $stmt, $name) = @_;

    my $hist = $dbh->{mock_all_history};
    is @$hist, @$stmt / 2,     
        "$name runs the right number of queries";

    while (my ($s, $b) = splice @$stmt, 0, 2) {
        my $h = shift @$hist;

        is $h->statement, $s,           "$name runs $s";
        is_deeply $h->bound_params, $b, 
            "$name binds the correct params to $s";
    }
}

1;
