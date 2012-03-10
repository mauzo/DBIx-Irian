use t::Util;
use t::Util::QS;

use DBIx::Irian undef, qw/lookup/;

my $D = setup_qs_checks "t::DB::Row";
my $dbh = $D->dbh;

my @row = ( [qw/a b c/], [1, 2, 3] );
register_mock_rows $D, (
    ["one",                                         @row],
    ["two",                                         @row],
    ["Q<one>, Q<two>, Q<three> FROM one",           @row],
    ["Q<un>, Q<deux>, Q<trois> FROM two",           @row],
    ["Q<one>, Q<two>, Q<three>, Q<four> FROM ext",
        [qw/a b c d/], [1, 2, 3, 4]],
);

sub check_row_query {
    my ($meth, $class, $res, $sql, $bind, $cols, $cant, $name) = @_;

    $dbh->{mock_clear_history} = 1;
    my $row = $D->$meth;
    isa_ok $row, $class,                $name;
    check_history "SELECT $sql", $bind, $name;

    ok $row->can($_),   "$name can $_"      for @$cols;
    ok !$row->can($_),  "$name can't $_"    for @$cant;
    is_deeply [map $row->$_, @$cols], $res,
                                        "$name returns correct results";

    ok $row->can('(@{}'),               "$name has \@{} overload";
    is_deeply [@$row], $res,            "$name overloads \@{} correctly";

    ok $row->can("_DB"),                "$name has _DB method";
    is $row->_DB, $D,                   "$name has correct _DB";

    return $row;
}

sub check_row_class {
    my ($class, $name) = @_;
    (my $pm = $class) =~ s!::!/!g;

    ok exists $INC{"$pm.pm"},               "$name is loaded";
    isa_ok $class, "DBIx::Irian::Row",      $name;
    isa_ok $class, "DBIx::Irian::QuerySet", $name;
    ok $class->can("_DB"),                  "$name can _DB";

    my $db = lookup $class, "db";
    ok $db,                                 "$name is registered";
    is $db, "t::DB::Row",                   "$name has correct DB";
}

check_row_class "t::DB::Row::One", "Row";
my $one = check_row_query 
    "one", "t::DB::Row::One", [1, 2, 3],
    "one", [], [qw/one two three/], [],
    "plain query";
do_all_qs_checks $one, "Row";

check_row_class "t::DB::Row::Two", "second Row";
check_row_query
    "two", "t::DB::Row::Two", [1, 2, 3],
    "two", [], [qw/un deux trois/], [qw/one two three/],
    "query with different Row";

check_row_class "t::Row::One",      "qualified Row";
check_row_query
    "q_one", "t::Row::One", [1, 2, 3],
    "one", [], [qw/one two three/], [],
    "query with qualified Row";

check_row_query
    "q_two", "t::DB::Row::Two", [1, 2, 3],
    "two", [], [qw/un deux trois/], [],
    "query with already-loaded qualified Row";

check_row_query
    "one_cols", "t::DB::Row::One", [1, 2, 3],
    "Q<one>, Q<two>, Q<three> FROM one", [], [qw/one two three/], [],
    "query with \$Cols";

check_row_query
    "two_cols", "t::DB::Row::Two", [1, 2, 3],
    "Q<un>, Q<deux>, Q<trois> FROM two", [], [qw/un deux trois/], [],
    "query with different \$Cols";

check_row_class "t::DB::Row::Ext", "extended Row";
my $ext = check_row_query
    "ext_cols", "t::DB::Row::Ext", [1, 2, 3, 4],
    "Q<one>, Q<two>, Q<three>, Q<four> FROM ext", [], 
        [qw/one two three four/], [],
    "query with extended Row";

isa_ok $ext, "t::DB::Row::One",     "extended Row inherits";
do_all_qs_checks $ext, "extended Row";

# I don't understand why I get these warnings...
no warnings "once";

check_row_class "t::DB::Row::Three", "explicitly loaded Row";
is $t::DB::Row::Three, "t::DB::Row::Three", 
                                    "row_class returns row class";
check_row_class "t::Row::Two",      "explicitly loaded qualified Row";
is $t::DB::Row::QTwo, "t::Row::Two",    "row_class returns qualified Row";

done_testing;
