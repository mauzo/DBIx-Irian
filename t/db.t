use t::Util;
use t::Util::QS;

my $D = setup_qs_checks "t::DB::DB";
do_all_qs_checks $D, "DB";

done_testing;
