package t::Util::QS;

use t::Util;
use Scalar::Util    qw/blessed/;

use Exporter "import";
our @EXPORT = qw(
    register_mock_rows setup_qs_checks
    check_detail check_action check_query check_cursor
    do_method_checks do_detail_checks do_action_checks do_query_checks
    do_cursor_checks do_qs_checks do_all_qs_checks
);

our ($D, $dbh, $callcb, $class);

sub setup_qs_checks {
    my ($mod) = @_;

    require_ok $mod;
    isa_ok $mod, "DBIx::Irian::DB";

    my $DB = $mod->new("dbi:Mock:");
    isa_ok $DB, $mod,                   "can construct a $mod";

    $dbh = $DB->dbh;

    register_mock_rows $DB, "SELECT", (
        ["detail",      ["d"], ["pv_detail"]    ],
        ["Q<q>",        ["q"], ["df_detail"]    ],
        ["? FROM plc",  ["p"], ["plc_detail"]   ],
        ["? FROM arg",  ["a"], ["arg_detail"]   ],
        ["? FROM self", ["s"], ["slf_detail"]   ],
    );

    my @query = ( [qw/a b c/], [qw/eins zwei drei/] );
    my @withq = (
        ["1, 2, 3",                             @query],
        ["Q<a>, Q<b>, Q<c>",                    @query],
        ["Q<one>, Q<two>, Q<three>",            @query],
        ["QQ<q|one>, QQ<q|two>, QQ<q|three>",   @query],
        ["?, 2, 3 FROM plc",                    @query],
        ["?, 2, 3 FROM arg",                    @query],
        ["?, 2, 3 FROM self",                   @query],
    );
    register_mock_rows $DB, "SELECT", @withq;
    register_mock_rows $DB, "FETCH 20 FROM SELECT", @withq;

    return $DB;
}

sub check_ctx {
    my ($m, $ck) = @_;

    $ck->("in scalar context", sub {
        my $rv = $callcb->($D, $m) or return;
        [$rv];
    });
    $ck->("in list context", sub {
        my @rv = $callcb->($D, $m) or return;
        \@rv;
    });
}

sub check_detail {
    my ($m, $sql, $bind, $nm) = @_;
    my $name = "detail on $class with $nm";

    check_ctx $m, sub {
        my ($ctx, $rv) = @_;
        $dbh->{mock_clear_history} = 1;

        is_deeply $rv->(), [$m],    "$name returns correct results $ctx";

        check_history $dbh, ["SELECT $sql", $bind], "$name $ctx";
    };
}

sub check_action {
    my ($m, $sql, $bind, $nm) = @_;
    my $name = "action on $class with $nm";

    check_ctx $m, sub {
        my ($ctx, $rv) = @_;
        $dbh->{mock_clear_history} = 1;

        ok $rv->(),                 "$name succeeds $ctx";
        check_history $dbh, ["INSERT $sql", $bind], "$name $ctx";
    };
}

my @stdrow = ("t::Row", [qw/one two three/], [qw/eins zwei drei/]);

sub check_query {
    my ($m, $sql, $bind, $nm) = @_;
    my $name = "query on $class with $nm";

    check_ctx $m, sub {
        my ($ctx, $cb) = @_;
        $dbh->{mock_clear_history} = 1;

        my $rv = $cb->();
        is @$rv, 1,                     "$name returns 1 row $ctx";

        check_row $$rv[0], @stdrow, "$name $ctx";
        check_history $dbh, ["SELECT $sql", $bind], "$name $ctx";
    };
}

sub check_cursor {
    my ($m, $sql, $bind, $nm) = @_;
    my $name = "cursor on $class with $nm";

    check_ctx $m, sub {
        my ($ctx, $rv) = @_;
        $dbh->{mock_clear_history} = 1;

        my $c = $rv->();
        is @$c, 1,                      "$name returns one value $ctx";

        $c = $$c[0];
        isa_ok $c, "DBIx::Irian::Cursor",   "$name $ctx";

        check_row $c->next, @stdrow,    "$name ->next $ctx";

        undef $c;

        check_history $dbh, [
            "DECLARE SELECT $sql",          $bind,
            "FETCH 20 FROM SELECT $sql",    [],
            "CLOSE SELECT $sql",            [],
        ], "$name $ctx";
    };
}

sub do_method_checks {
    ok $D->can($_), "$class can $_" for qw/ cv_meth pv_meth df_meth method /;
    is $D->cv_meth, "foo",      "method on $class with a subref";
    is $D->pv_meth, "foo",      "method on $class with a plain string";
    is $D->method,  "foo",      "method on $class called 'method'";
    check_defer $D->df_meth, "%", {db => $DB}, ["Q<foo>"],
                                "method on $class with a Query";
}

sub do_detail_checks {
    check_detail pv_detail => "detail", [], "plain string";
    check_detail df_detail => "Q<q>", [],   "Query";
    check_detail plc_detail => "? FROM plc", ["p"],
                                            "placeholder";
    check_detail arg_detail => "? FROM arg", ["arg0"],
                                            "\@Arg";
    check_detail slf_detail => "? FROM self", ["foo"],
                                            "%Self";
}

sub do_action_checks {
    check_action pv_action => "action", [], "plain string";
    check_action df_action => "Q<q>", [],   "Query";
    check_action plc_action => "? INTO plc", ["p"],
                                            "placeholder";
    check_action arg_action => "? INTO arg", ["arg0"],
                                            "\@Arg";
    check_action slf_action => "? INTO self", ["foo"],
                                            "%Self";
}

sub do_query_checks {
    check_query pv_query => "1, 2, 3", [],  "plain string";
    check_query df_query => "Q<a>, Q<b>, Q<c>", [],
                                            "Query";
    check_query col_query => "Q<one>, Q<two>, Q<three>", [],
                                            "\$Cols";
    check_query qcl_query => "QQ<q|one>, QQ<q|two>, QQ<q|three>", [],
                                            "%Cols";
    check_query plc_query => "?, 2, 3 FROM plc", ["p"],
                                            "%P";
    check_query arg_query => "?, 2, 3 FROM arg", ["arg0"],
                                            "\@Arg";
    check_query slf_query => "?, 2, 3 FROM self", ["foo"],
                                            "%Self";
}

sub do_cursor_checks {
    check_cursor pv_cursor => "1, 2, 3", [],  "plain string";
    check_cursor df_cursor => "Q<a>, Q<b>, Q<c>", [],
                                            "Query";
    check_cursor col_cursor => "Q<one>, Q<two>, Q<three>", [],
                                            "\$Cols";
    check_cursor qcl_cursor => "QQ<q|one>, QQ<q|two>, QQ<q|three>", [],
                                            "%Cols";
    check_cursor plc_cursor => "?, 2, 3 FROM plc", ["p"],
                                            "%P";
    check_cursor arg_cursor => "?, 2, 3 FROM arg", ["arg0"],
                                            "\@Arg";
    check_cursor slf_cursor => "?, 2, 3 FROM self", ["foo"],
                                            "%Self";
}

sub do_qs_checks {
    my $cb = pop;
    local ($D, $class, $callcb) = @_;
    $cb->();
}

sub do_all_qs_checks {
    do_qs_checks @_, sub { 
        my ($D, $m) = @_;
        ok $D->can($m), "method $m exists on $class";
        $D->$m("arg0");
    }, sub {
        do_method_checks;
        do_detail_checks;
        do_query_checks;
        do_cursor_checks;
        do_action_checks;
    };
}

1;
