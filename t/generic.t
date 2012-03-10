use t::Util;
use t::Util::QS;
use DBIx::Irian undef, "lookup";

my $DB = "t::DB::Generic";
my $G  = "DBIx::Irian::Row::Generic";

require_ok $DB;
isa_ok $DB, "DBIx::Irian::DB",  "DB with Row::Generic";

isa_ok $G, "DBIx::Irian::Row",  "Row::Generic";
ok !lookup($G, "db"),           "Row::Generic has no DB";
ok $G->can("_new"),             "Row::Generic can _new";

my $D = $DB->new("dbi:Mock:");

sub check_generic {
    my ($row, $fields, $values, $name) = @_;

    isa_ok $row, $G,            $name;
    ok $row->can("_DB"),        "$name has a _DB method";
    is $row->_DB, $D,           "$name has correct _DB";

    for (0..$#$fields) {
        my $f = $$fields[$_];
        ok $row->can($f),                       "$name can $f";
        is eval { $row->$f } , $$values[$_],    "$name has correct $f";
    }
}

register_mock_rows $D, (
    ["a, b FROM query", ["a", "b"],             [1, 2]      ],
    ["c, d FROM query", ["c", "d"],             [3, 4]      ],
    ["cursor",          [qw/un deux trois/],    [4, 5, 6]   ],
    ["explicit",        [qw/eins zwei drei/],   [7, 8, 9]   ],
);

check_generic $G->_new($D, [1, 2, 3], [qw/one two three/]),
    [qw/one two three/], [1, 2, 3],
    "new Row::Generic";

check_generic $G->_new($D, [6, 7], [qw/blib blob/]),
    [qw/blib blob/], [6, 7],
    "new Row::Generic with different fields";

check_generic $D->gen_ab, ["a", "b"], [1, 2],
    "Row::Generic from query";

check_generic $D->gen_cd, ["c", "d"], [3, 4],
    "different Row::Generic from query";

TODO: {
     local $TODO = "Row::Generic with cursors";

check_generic $D->gen_curs->next, [qw/un deux trois/], [4, 5, 6],
    "Row::Generic from cursor";
}

ok !eval {
    local $SIG{__WARN__} = sub {};
    package t::DB::Generic::Two;
    use DBIx::Irian "DB";
    query foo => "+DBIx::Irian::Row::Generic" => "SELECT explicit";
    1;
},              "explicit Row::Generic fails";
like $@, qr/^Not a Row class: DBIx::Irian::Row::Generic/,
                "explicit R::G throws correct error";

done_testing;
