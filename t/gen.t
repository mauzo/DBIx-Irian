use t::Util;
use DBIx::Irian undef, "lookup";

exp_require_ok "t::DB::Gen";
isa_ok "t::DB::Gen", "DBIx::Irian::DB";

my $D = t::DB::Gen->new("dbi:Mock:");
isa_ok $D, "t::DB::Gen",                "can construct a Gen'd DB";

my @row = ( [qw/a b c/], [1, 2, 3] );
register_mock_rows $D, "SELECT", (
    ["gen",     @row],
    ["gen2",    @row],
    ["qgen",    @row],
);

sub check_gen {
    my ($m, $class, $fields, $name) = @_;
    (my $pm = $class) =~ s!::!/!g;

    isa_ok $class, "DBIx::Irian::Row",      $name;
    ok $INC{"$pm.pm"},                      "$name has an %INC entry";

    my $db = lookup $class, "db";
    ok $db,                                 "$name is registered";
    is $db, "t::DB::Gen",                   "$name is in correct DB";

    ok $D->can($m),                         "method exists for $name";

    my $row = $D->$m;
    isa_ok $row, $class,                    $name;
    isa_ok $row, "DBIx::Irian::Row",        $name;
    ok $row->can("_DB"),                    "$name has _DB method";
    is $row->_DB, $D,                       "$name has correct _DB";

    ok $row->can($_), "$name can $_" for @$fields;
    is_deeply [map $row->$_, @$fields], [1, 2, 3],
                                            "$name has correct values";
}

check_gen "gen", "t::DB::Gen::Gen", [qw/one two three/], 
    "generated Row";
check_gen "gen2", "t::DB::Gen::Gen2", [qw/unos dos tres/],
    "second generated Row";
check_gen "qgen", "t::Gen", [qw/un deux trois/],
    "qualified generated Row";

done_testing;
