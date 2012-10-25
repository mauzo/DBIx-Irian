use t::Util;
use t::Util::QS;

my $D = setup_qs_checks "t::DB::DB";
do_all_qs_checks $D, "DB";

our %QS;
do "t/QS.pl";

for (qw/do_query do_cursor do_detail do_action/) {
    ok $D->can($_), "method $_ exists on DB";
}

use DBIx::Irian::Query;

do_qs_checks $D, "DB (using do_*)", sub {
    my ($D, $k) = @_;
    my ($m, $sql) = @{$QS{$k}};
    my @row = $m eq "query" || $m eq "cursor" 
        ? "t::Row" : ();
    $m = "do_$m";
    $D->$m(@row, eval $sql, { self => $D, args => ["arg0"] });
}, sub {
    do_query_checks;
    do_cursor_checks;
    do_detail_checks;
    do_action_checks;
};

done_testing;
