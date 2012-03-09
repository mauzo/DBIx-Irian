package t::DB::Row;

use DBIx::Irian "DB";

query one => One => "SELECT one";
query two => Two => "SELECT two";

query one_cols => One => "SELECT $Cols FROM one";
query two_cols => Two => "SELECT $Cols FROM two";
query ext_cols => Ext => "SELECT $Cols FROM ext";

our $Three = row_class "Three";

1;
