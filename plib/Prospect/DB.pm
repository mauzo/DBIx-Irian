package Prospect::DB;

use DBIx::OQM "DB";

query book => Book => <<SQL;
    SELECT $Cols FROM book WHERE isbn = $Arg[0]
SQL

query books => Book => "SELECT $Cols FROM book";

1;
