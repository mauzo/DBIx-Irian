package t::DB::Cursor;
use DBIx::Irian "DB";

setup_row_class Row => qw/one two three/;
cursor curs => Row => "SELECT sugar";
cursor args => Row => "SELECT $Arg[0] FROM args";

1;
