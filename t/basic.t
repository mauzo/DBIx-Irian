use t::Util;
use t::Util::QS;

my $D = setup_qs_checks "t::DB::Basic";
do_all_qs_checks $D;

done_testing;
