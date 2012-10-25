package t::DB::Row::One;

use t::Util::DB;

use DBIx::Irian "Row";
columns qw/one two three/;

BEGIN { eval setup_qs_methods }
method method => sub { "foo" };

1;
