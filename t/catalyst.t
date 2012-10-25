use t::Util;

BEGIN {
    eval { require Catalyst::Model }
        or plan skip_all => "No Catalyst";

    # just in case
    delete @ENV{qw/CATALYST_DEBUG IRIAN_TRACE DBI_TRACE/};
}

use t::Util::Subproc;
use Scalar::Util    qw/blessed/;

require_ok "t::Cat";

subproc {
    my $App = t::Cat->build_app_ok(undef, "using M::Irian");

    my $DB  = t::Cat->model("Irian");

    ok blessed $DB,                 "->model on a Cat app returns an object";
    isa_ok $DB, "DBIx::Irian::DB",  "->model on a Cat app";
    isa_ok $DB, "t::DB::DB",        "->model on a Cat app";

    my $DB2 = t::Cat->model("Irian");
    is $DB2, $DB,                   "->model returns the same DB each time";
};

DBIx::Irian::set_trace_flags("TST" => 1);

for (
    [1          => "[debug]"    ],
    [debug      => "[debug]"    ],
    [info       => "[info]"     ],
) {
    my ($redir, $pfx) = @$_;
    my $with = "with redirect_trace => $redir";

    subproc {
        use DBIx::Irian undef, qw/trace/;

        my $App = t::Cat->build_app_ok(
            { "Model::Irian", { redirect_trace => $redir } },
            $with);

        my $log = $App->log;
        my $DB  = $App->model("DB");

        trace TST => "foo";
        my @trc = $log->_fetch_from_log;

        is_deeply \@trc, ["$pfx TST: foo"],
                                    "Irian logs through Cat $with";

        $log->_fetch_from_log;
        DBI->trace(1);
        DBI->trace_msg("bar\n");
        DBI->trace(0);
        @trc = grep !/trace level set/, $log->_fetch_from_log;

        is_deeply \@trc, ["$pfx DBI: bar"],
                                    "DBI logs through Cat $with";
    };
}

done_testing;
