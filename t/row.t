use t::Util;
use t::Util::QS;

my $D = setup_qs_checks "t::DB::Row";

my @row = ( [qw/a b c/], [1, 2, 3] );
register_mock_rows $D, (
    ["one",                                         @row],
    ["two",                                         @row],
    ["Q<one>, Q<two>, Q<three> FROM one",           @row],
    ["Q<un>, Q<deux>, Q<trois> FROM two",           @row],
    ["Q<one>, Q<two>, Q<three>, Q<four> FROM ext",
        [qw/a b c d/], [1, 2, 3, 4]],
);
    
my $one = $D->one;
isa_ok $one, "t::DB::Row::One",     "query returns correct Row";

my @en = qw/one two three/;
can_ok $one, $_ for @en;
is_deeply [map $one->$_, @en], [1, 2, 3],
                                    "query returns correct results";

do_all_qs_checks $one;

my $two = $D->two;
isa_ok $two, "t::DB::Row::Two",     "queries can return different Rows";

my @fr = qw/un deux trois/;
can_ok $two, $_ for @fr;
ok !$two->can($_), "Row::Two can't ->$_" for @en;
is_deeply [map $two->$_, @fr], [1, 2, 3],
                                    "second query returns correct results";

my $ext = $D->ext_cols;
do_all_qs_checks $ext;

done_testing;
