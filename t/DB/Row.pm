package t::DB::Row;

use DBIx::Irian "DB";

query one => One => "SELECT one";
query two => Two => "SELECT two";
 
query q_one => "+t::Row::One"       => "SELECT one";
query q_two => "+t::DB::Row::Two"   => "SELECT two";

query one_cols => One => "SELECT $Cols FROM one";
query two_cols => Two => "SELECT $Cols FROM two";
query ext_cols => Ext => "SELECT $Cols FROM ext";

our $Three  = row_class "Three";
our $QTwo   = row_class "+t::Row::Two";

1;
