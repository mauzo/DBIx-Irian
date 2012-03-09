sub foo { "foo" }

method cv_meth => sub { "foo" };
method pv_meth => "foo";
method df_meth => $Q{foo};
method method => sub { "foo" };

detail pv_detail    => "SELECT detail";
detail df_detail    => "SELECT $Q{q}";
detail plc_detail   => "SELECT $P{p} FROM plc";
detail arg_detail   => "SELECT $Arg[0] FROM arg";
detail slf_detail   => "SELECT $Self{foo} FROM self";

action pv_action    => "INSERT action";
action df_action    => "INSERT $Q{q}";
action plc_action   => "INSERT $P{p} INTO plc";
action arg_action   => "INSERT $Arg[0] INTO arg";
action slf_action   => "INSERT $Self{foo} INTO self";

query pv_query  => "+t::Row" => "SELECT 1, 2, 3";
query df_query  => "+t::Row" => "SELECT $Q{a}, $Q{b}, $Q{c}";
query col_query => "+t::Row" => "SELECT $Cols";
query qcl_query => "+t::Row" => "SELECT $Cols{q}";
query plc_query => "+t::Row" => "SELECT $P{p}, 2, 3 FROM plc";
query arg_query => "+t::Row" => "SELECT $Arg[0], 2, 3 FROM arg";
query slf_query => "+t::Row" => "SELECT $Self{foo}, 2, 3 FROM self";

cursor pv_cursor  => "+t::Row" => "SELECT 1, 2, 3";
cursor df_cursor  => "+t::Row" => "SELECT $Q{a}, $Q{b}, $Q{c}";
cursor col_cursor => "+t::Row" => "SELECT $Cols";
cursor qcl_cursor => "+t::Row" => "SELECT $Cols{q}";
cursor plc_cursor => "+t::Row" => "SELECT $P{p}, 2, 3 FROM plc";
cursor arg_cursor => "+t::Row" => "SELECT $Arg[0], 2, 3 FROM arg";
cursor slf_cursor => "+t::Row" => "SELECT $Self{foo}, 2, 3 FROM self";

