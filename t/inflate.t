use t::Util;

use Scalar::Util    qw/reftype blessed/;

sub check_inflator {
    my ($key, $ck, $name) = @_;

    my $inf = DBIx::Irian::Inflate->lookup($key);
    ok $inf,                    "$name exists";
    ok ref $inf && !blessed $inf && reftype $inf eq "CODE",
                                "$name is a coderef";
    ok eval { $ck->($inf) },    "$name runs correctly"
        or diag "\$\@: $@";
}

sub check_inf_row {
    my ($row, $fields, $name) = @_;
    for (@$fields) {
        my ($m, $want, $fname) = @$_;
        my $fn = "field with $fname";
        
        ok $row->can($m),           "$name has method for $fn";
        is $row->$m, $want,         "$fn on $name inflates correctly";
    }
}

my $DB = "t::DB::Inflate";

require_ok $DB;
isa_ok $DB, "DBIx::Irian::DB",      "DB with inflators";

ok eval {
    ok !defined(DBIx::Irian::Inflate->lookup(undef)),
        "Inflate->lookup(undef) returns undef";
    1;
},      "Inflate->lookup(undef) doesn't throw";

check_inflator "foo", sub { $_[0]->("bar") eq "foobar" },
    "inflator registered by DB";
check_inflator "bar", sub { $_[0]->("foo") eq "barfoo" },
    "inflator registered by Row";

SKIP: {
    eval { require Business::ISBN } or skip "No Business::ISBN", 1;

    check_inflator "ISBN", 
        sub { $_[0]->("190301820X")->isa("Business::ISBN") },
        "standard 'ISBN' inflator";
}

my $D = $DB->new("dbi:Mock:");

register_mock_rows $D, (
   ["inf",      [qw/a b c/],        [1, 1, 1]],
   ["ext",      [qw/a b c d e/],    [1, 1, 1, 1, 1]],
);

my @inf = (
    ["plain",   1,      "no inflator"       ],
    ["foo",     "foo1", "inflator on DB"    ],
    ["bar",     "bar1", "inflator on Row"   ],
);
my @ext = (
    map([@$_[0,1], "$$_[2] (inherited)"], @inf),
    ["plain",   1,      "no inflator (extended)"  ],
    ["foo",     "foo1", "inflator (extended)"     ],
);

check_inf_row "$DB\::Inf"->_new($D, [1, 1, 1]), \@inf, 
    "new Row";
check_inf_row "$DB\::Ext"->_new($D, [1, 1, 1, 1, 1]), \@ext,
    "new extended Row";
check_inf_row $D->inf, \@inf,
    "queried Row";
check_inf_row $D->ext, \@ext,
    "queried extended Row";
    
done_testing;
