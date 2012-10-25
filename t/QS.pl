%QS = (
    cv_meth     => [method => q{sub { 'foo' }}],
    pv_meth     => [method => q{"foo"}],
    df_meth     => [method => q{$Q{foo}}],
     
    pv_detail   => [detail  => q{"SELECT detail"}],
    df_detail   => [detail  => q{"SELECT $Q{q}"}],
    plc_detail  => [detail  => q{"SELECT $P{p} FROM plc"}],
    arg_detail  => [detail  => q{"SELECT $Arg[0] FROM arg"}],
    slf_detail  => [detail  => q{"SELECT $Self{foo} FROM self"}],
     
    pv_action   => [action  => q{"INSERT action"}],
    df_action   => [action  => q{"INSERT $Q{q}"}],
    plc_action  => [action  => q{"INSERT $P{p} INTO plc"}],
    arg_action  => [action  => q{"INSERT $Arg[0] INTO arg"}],
    slf_action  => [action  => q{"INSERT $Self{foo} INTO self"}],
     
    pv_query    => [query   => q{"SELECT 1, 2, 3"}],
    df_query    => [query   => q{"SELECT $Q{a}, $Q{b}, $Q{c}"}],
    col_query   => [query   => q{"SELECT $Cols"}],
    qcl_query   => [query   => q{"SELECT $Cols{q}"}],
    plc_query   => [query   => q{"SELECT $P{p}, 2, 3 FROM plc"}],
    arg_query   => [query   => q{"SELECT $Arg[0], 2, 3 FROM arg"}],
    slf_query   => [query   => q{"SELECT $Self{foo}, 2, 3 FROM self"}],
     
    pv_cursor   => [cursor  => q{"SELECT 1, 2, 3"}],
    df_cursor   => [cursor  => q{"SELECT $Q{a}, $Q{b}, $Q{c}"}],
    col_cursor  => [cursor  => q{"SELECT $Cols"}],
    qcl_cursor  => [cursor  => q{"SELECT $Cols{q}"}],
    plc_cursor  => [cursor  => q{"SELECT $P{p}, 2, 3 FROM plc"}],
    arg_cursor  => [cursor  => q{"SELECT $Arg[0], 2, 3 FROM arg"}],
    slf_cursor  => [cursor  => q{"SELECT $Self{foo}, 2, 3 FROM self"}],
);
