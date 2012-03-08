use t::Util;
use DBIx::Irian::Query;

check_defer $Q{foo}, "%", { db => $DB }, ["Q<foo>"],    "%Q";
check_defer $Q{foo}, "%", { db => 1, dbh => $DBH }, ["Q<foo>"],
                                "%Q with explicit dbh";

check_defer $P{bar}, "?", {}, ["?", "bar"],             "%P";

{   package t::FakeSelf;
    sub foo { uc $_[0][0] }
    sub bar { 1 }
    sub baz { "a" }
}

sub check_var {
    my ($q, $str, $exp, $name) = @_;
    for my $v qw(one two) {
        s/%/$v/g, s/~/\U$v/g for my @exp = @$exp;
        check_defer $q, $str, { 
            args    => [a => $v, b => "foo"], 
            self    => bless([$v], "t::FakeSelf"),
            db      => $DB,
            row     => {
                cols => [qw/exs wye zed/],
            },
        }, \@exp, "$name ($v)";
    }
}

for ([$ArgX[1], '@ArgX'], [$ArgX{a}, '%ArgX']) {
    my ($q, $nm) = @$_;

    check_var $q, "%", ["%"],               $nm;
    check_var "foo$q", "foo%", ["foo%"],    "$nm interpolated";
    check_var $Q{$q}, "%", ["Q<%>"],        "%Q $nm";
    check_var $P{$q}, "?", ["?", "%"],      "%P $nm";
}

check_var $ArgQ[1], "%", ["Q<%>"],          '@ArgQ';
check_var $ArgQ{a}, "%", ["Q<%>"],          '%ArgQ';
check_var $Arg[1],  "?", ["?", "%"],        '@Arg';
check_var $Arg{a},  "?", ["?", "%"],        '%Arg';

{
    my $q = $SelfX{foo};

    check_var $q, "%", ["~"],               '%SelfX';
    check_var "foo$q", "foo%", ["foo~"],    '%SelfX interpolated';
    check_var $Q{$q}, "%", ["Q<~>"],        '%Q %SelfX';
    check_var $P{$q}, "?", ["?", "~"],      '%P %SelfX';
}

check_var $SelfQ{foo}, "%", ["Q<~>"],       '%SelfQ';
check_var $Self{foo},  "?", ["?", "~"],     '%Self';

# XXX no nesting yet

check_var $Cols, "%", ["Q<exs>, Q<wye>, Q<zed>"],               '$Cols';
check_var $Cols{q}, "%", ["QQ<q|exs>, QQ<q|wye>, QQ<q|zed>"],   '%Cols';

done_testing;
