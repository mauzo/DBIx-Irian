package t::DB::Generic;

use DBIx::Irian "DB";

query   gen_ab      => "" => "SELECT a, b FROM query";
query   gen_cd      => "" => "SELECT c, d FROM query";
cursor  gen_curs    => "" => "SELECT cursor";

1;
