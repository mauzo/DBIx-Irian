package t::DB::DB;

use DBIx::Irian "DB";
use t::Util::DB;

# BEGIN eval since the sugar will disappear after compile time
BEGIN { eval setup_qs_methods }

# This must appear outside the eval to avoid conflicting with the
# 'method' sugar.
method method => sub { "foo" };

1;
