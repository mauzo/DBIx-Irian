package t::QS;

use t::Util::DB;

use DBIx::Irian "QuerySet";

BEGIN { eval setup_qs_methods }
method method => sub { "foo" };

1;
