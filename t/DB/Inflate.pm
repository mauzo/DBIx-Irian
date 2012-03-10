package t::DB::Inflate;
use DBIx::Irian "DB", "register_inflators";

register_inflators foo => sub { "foo" . $_[0] };

query inf => Inf => "SELECT inf";
query ext => Ext => "SELECT ext";

1;
