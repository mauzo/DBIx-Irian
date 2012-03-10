package t::DB::Inflate::Inf;

use DBIx::Irian "Row", "register_inflators";

register_inflators bar => sub { "bar" . $_[0] };

columns qw/plain foo bar/;
inflate foo => "foo", bar => "bar";

1;
