use t::Util;
use DBIx::Irian         undef, "djoin";
use DBIx::Irian::Query;

check_defer $Defer->new("foo"), "foo", {}, ["foo"], 
                                "defer from plain string";
check_defer $Defer->new(sub { "foo" }), "%", {}, ["foo"],
                                "defer from subref";
check_defer $Defer->new("?", sub { "bar" }), "?", {}, ["?", "bar"],
                                "placeholder";
check_defer $Defer->new(sub { $_[0]{d} }, sub { $_[0]{p} }),
    "%", { d => "foo", p => "bar" }, ["foo", "bar"],
                                "dynamic deferral";
{
    my $q = $Defer->new(sub { "foo" });
    my $r = $q . "bar";
    check_defer $r, "%bar", {}, ["foobar"], "concat";

    my $s = "$q bar";
    check_defer $s, "% bar", {}, ["foo bar"], "interp";

    my $t = "baz$r";
    check_defer $t, "baz%bar", {}, ["bazfoobar"], "multiple concats";

    my $u = djoin ":", $q, $r;
    check_defer $u, "%:%bar", {}, ["foo:foobar"], "djoin";

    my $v = djoin $q, "+", "-", "*";
    check_defer $v, "+%-%*", {}, ["+foo-foo*"], "djoin on defer";
}

done_testing;
