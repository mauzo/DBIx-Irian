package t::Util::QS;

use t::Util;

use Exporter "import";
our @EXPORT = qw(
    register_mock_rows setup_qs_checks
    check_history check_detail check_action check_row check_query
    check_cursor
    do_method_checks do_detail_checks do_action_checks do_query_checks
    do_cursor_checks do_all_qs_checks
);

my ($D, $dbh);

sub register_mock_rows {
    my ($dbh) = @_;

    my @query = ( [qw/a b c/], [qw/eins zwei drei/] );

    for (
        ["detail",      ["d"], ["pv_detail"]    ],
        ["Q<q>",        ["q"], ["df_detail"]    ],
        ["? FROM plc",  ["p"], ["plc_detail"]   ],
        ["? FROM arg",  ["a"], ["arg_detail"]   ],
        ["? FROM self", ["s"], ["slf_detail"]   ],

        ["1, 2, 3",                             @query],
        ["Q<a>, Q<b>, Q<c>",                    @query],
        ["Q<one>, Q<two>, Q<three>",            @query],
        ["QQ<q|one>, QQ<q|two>, QQ<q|three>",   @query],
        ["?, 2, 3 FROM plc",                    @query],
        ["?, 2, 3 FROM arg",                    @query],
        ["?, 2, 3 FROM self",                   @query],
    ) {
        my ($sql, @rows) = @$_;
        $dbh->{mock_add_resultset} = {
            sql     => "SELECT $sql",
            results => \@rows,
        };
    }
}

sub setup_qs_checks {
    my ($mod) = @_;

    exp_require_ok $mod;

    $D = $mod->new("dbi:Mock:");
    isa_ok $D, $mod,                    "can construct a $mod";

    $dbh = $D->dbh;
    register_mock_rows $dbh;
}

sub check_history {
    my ($sql, $bind, $name) = @_;

    my $hist = $dbh->{mock_all_history};
    is @$hist, 1,                       "$name runs 1 query";

    my $h = $hist->[0];
    is $h->statement, $sql,             "$name runs the correct SQL";
    is_deeply $h->bound_params, $bind,  "$name binds the correct params";
}

sub check_detail {
    my ($m, $sql, $bind, $name) = @_;
    $dbh->{mock_clear_history} = 1;

    my @rv = $D->$m("arg0");
    is_deeply \@rv, [$m],               "$name returns correct results";

    check_history "SELECT $sql", $bind, $name;
}

sub check_action {
    my ($m, $sql, $bind, $name) = @_;
    $dbh->{mock_clear_history} = 1;

    ok $D->$m("arg0"),                  "$name succeeds";
    check_history "INSERT $sql", $bind, $name;
}

my $row = [qw/eins zwei drei/];
sub check_row {
    my ($r, $name) = @_;

    isa_ok $r, "t::DB::Basic::Row",     $name;

    my @r = [map $r->$_, qw/one two three/];
    is_deeply @r, $row,                 "$name returns correct row";
}

sub check_query {
    my ($m, $sql, $bind, $name) = @_;
    $dbh->{mock_clear_history} = 1;

    my @rv = $D->$m("arg0");
    is @rv, 1,                          "$name returns 1 row";

    check_row $rv[0], $name;
    check_history "SELECT $sql", $bind, $name;
}

sub check_cursor {
    my ($m, $sql, $bind, $name) = @_;
    $dbh->{mock_clear_history} = 1;
    
    my $c = $D->$m("arg0");
    isa_ok $c, "DBIx::Irian::Cursor",   $name;

    check_row $c->next,                 "$name ->next";
    ok !defined $c->next,               "$name returns 1 row";

    check_history "SELECT $sql", $bind, $name;
}

sub do_method_checks {
    can_ok $D, $_ for qw/ cv_meth pv_meth df_meth method /;
    is $D->cv_meth, "foo",      "method with a subref";
    is $D->pv_meth, "foo",      "method with a plain string";
    is $D->method,  "foo",      "method called 'method'";
    check_defer $D->df_meth, "%", {db => $DB}, ["Q<foo>"],
                                "method with a Query";
}

sub do_detail_checks {
    can_ok $D, "$_\_detail" for qw/pv df plc arg slf/;

    check_detail pv_detail => "detail", [], "detail with plain string";
    check_detail df_detail => "Q<q>", [],   "detail with Query";
    check_detail plc_detail => "? FROM plc", ["p"],
                                            "detail with placeholder";
    check_detail arg_detail => "? FROM arg", ["arg0"],
                                            "detail with \@Arg";
    check_detail slf_detail => "? FROM self", ["foo"],
                                            "detail with %Self";
}

sub do_action_checks {
    can_ok $D, "$_\_action" for qw/pv df plc arg slf/;

    check_action pv_action => "action", [], "action with plain string";
    check_action df_action => "Q<q>", [],   "action with Query";
    check_action plc_action => "? INTO plc", ["p"],
                                            "action with placeholder";
    check_action arg_action => "? INTO arg", ["arg0"],
                                            "action with \@Arg";
    check_action slf_action => "? INTO self", ["foo"],
                                            "action with %Self";
}

sub do_query_checks {
    can_ok $D, "$_\_query" for qw/pv df col qcl plc arg slf/;

    check_query pv_query => "1, 2, 3", [],  "query with plain string";
    check_query df_query => "Q<a>, Q<b>, Q<c>", [],
                                            "query with Query";
    check_query col_query => "Q<one>, Q<two>, Q<three>", [],
                                            "query with \$Cols";
    check_query qcl_query => "QQ<q|one>, QQ<q|two>, QQ<q|three>", [],
                                            "query with %Cols";
    check_query plc_query => "?, 2, 3 FROM plc", ["p"],
                                            "query with %P";
    check_query arg_query => "?, 2, 3 FROM arg", ["arg0"],
                                            "query with \@Arg";
    check_query slf_query => "?, 2, 3 FROM self", ["foo"],
                                            "query with %Self";
}

sub do_cursor_checks {
    can_ok $D, "$_\_cursor" for qw/pv df col qcl plc arg slf/;

    check_cursor pv_cursor => "1, 2, 3", [],  "cursor with plain string";
    check_cursor df_cursor => "Q<a>, Q<b>, Q<c>", [],
                                            "cursor with Query";
    check_cursor col_cursor => "Q<one>, Q<two>, Q<three>", [],
                                            "cursor with \$Cols";
    check_cursor qcl_cursor => "QQ<q|one>, QQ<q|two>, QQ<q|three>", [],
                                            "cursor with %Cols";
    check_cursor plc_cursor => "?, 2, 3 FROM plc", ["p"],
                                            "cursor with %P";
    check_cursor arg_cursor => "?, 2, 3 FROM arg", ["arg0"],
                                            "cursor with \@Arg";
    check_cursor slf_cursor => "?, 2, 3 FROM self", ["foo"],
                                            "cursor with %Self";
}

sub do_all_qs_checks {
    my ($mod) = @_;

    setup_qs_checks $mod;

    do_method_checks;
    do_detail_checks;
    do_query_checks;
    do_cursor_checks;
    do_action_checks;
}

1;
