package t::Util;

use warnings;
use strict;

require Exporter;
our @EXPORT = qw/
    fakerequire $Defer check_defer $DB $DBH register_mock_rows
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

sub register_mock_rows {
    my ($dbh) = @_;

    my @query = ( [qw/a b c/], [qw/eins zwei drei/] );

    for (
        ["detail",      ["d"], ["pv_detail"]    ],
        ["Q<q>",        ["q"], ["df_detail"]    ],
        ["? FROM plc",  ["p"], ["plc_detail"]   ],
        ["? FROM arg",  ["a"], ["arg_detail"]   ],
        ["? FROM self", ["s"], ["slf_detail"]   ],

        ["1, 2, 3",                             @query],
        ["Q<a>, Q<b>, Q<c>",                    @query],
        ["Q<one>, Q<two>, Q<three>",            @query],
        ["QQ<q|one>, QQ<q|two>, QQ<q|three>",   @query],
        ["?, 2, 3 FROM plc",                    @query],
        ["?, 2, 3 FROM arg",                    @query],
        ["?, 2, 3 FROM self",                   @query],
    ) {
        my ($sql, @rows) = @$_;
        $dbh->{mock_add_resultset} = {
            sql     => "SELECT $sql",
            results => \@rows,
        };
    }
}

1;
