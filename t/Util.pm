package t::Util;

use warnings;
use strict;

require Exporter;
our @EXPORT = qw/
    slurp fakerequire exp_require_ok
    $Defer check_defer $DB $DBH register_mock_rows
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

sub exp_require_ok {
    my ($mod) = @_;
    my $B = Test::More->builder;

    local @INC = (sub {
        my (undef, $pm) = @_;
        $pm =~ m!^t/! or return;

        my $perl = slurp $pm;
        $perl =~ s{%%([a-zA-Z/]+)%%}{ slurp "t/$1.pl" }ge;

        open my $PERL, "<", \$perl;
        return $PERL;
    }, @INC);

    (my $pm = $mod) =~ s!::!/!g;    
    my $ok = eval { require "$pm.pm"; 1; };

    $B->ok($ok, "require $mod with expansion")
        or $B->diag("\$\@: $@");
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
    my ($db, @rows) = @_;
    my $dbh = $db->dbh;
    for (@rows) {
        my ($sql, @rows) = @$_;
        $dbh->{mock_add_resultset} = {
            sql     => "SELECT $sql",
            results => \@rows,
        };
    }
}
1;
