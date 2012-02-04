package Prospect::DB::Book;

use DBIx::OQM "Row";

columns qw/id isbn title subtitle/;

query reviews => Review => <<SQL;
    SELECT $Cols FROM review WHERE of = $Self{id}
SQL

1;
