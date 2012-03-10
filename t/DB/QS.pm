package t::DB::QS;

use DBIx::Irian "DB";

queryset qs     => "QS";
queryset qqs    => "+t::QS";
queryset qs2    => "+t::DB::QS::QS";

1;
