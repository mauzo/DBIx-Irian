package t::DB::Gen;

use DBIx::Irian "DB";

setup_row_class "Gen",      qw/one two three/;
setup_row_class "Gen2",     qw/unos dos tres/;
setup_row_class "+t::Gen",  qw/un deux trois/;

query gen   => Gen          => "SELECT gen";
query gen2  => Gen2         => "SELECT gen2";
query qgen  => "+t::Gen"    => "SELECT qgen";

1;
