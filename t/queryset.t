use t::Util;
use t::Util::QS;

my $D = setup_qs_checks "t::DB::QS";

sub check_qs {
    my ($m, $class, $name) = @_;
    (my $pm = $class) =~ s!::!/!g;

    ok $INC{"$pm.pm"},                      "$name loaded";
    ok $D->can($m),                         "method exists for $name";
    
    my $qs = $D->$m;
    isa_ok $qs, "DBIx::Irian::QuerySet",    $name;
    isa_ok $qs, $class,                     $name;
    ok $qs->can("_DB"),                     "$name has _DB method";
    is $qs->_DB, $D,                        "$name has correct _DB";

    do_all_qs_checks $qs, $name;
}

check_qs "qs",  "t::DB::QS::QS",    "QuerySet";
check_qs "qqs", "t::QS",            "qualified QuerySet";
check_qs "qs2", "t::DB::QS::QS",    "qualified already-loaded QS";

done_testing;
