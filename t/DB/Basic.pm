package t::DB::Basic;

use DBIx::Irian "DB";

setup_row_class Row => qw/one two three/;

%%QS%%

1;
