use t::Util;
use t::Util::QS;

my $D = setup_qs_checks "t::DB::DB";
do_all_qs_checks $D, "DB";

my %sql;
{
    no warnings "once";
    use DBIx::Irian::Query;
    local *method = sub { 1 };
    for (\local (*action, *detail, *cursor, *query)) {
        (my $type = *$_) =~ s/.*:://;
        *$_ = sub { 
            my $n = shift;
            $sql{$n} = ["do_$type", @_];
        };
    }

    require "t/QS.pl";
}

for (qw/do_query do_cursor do_detail do_action/) {
    ok $D->can($_), "method $_ exists on DB";
}

do_qs_checks $D, "DB (using do_*)", sub {
    my ($D, $k) = @_;
    my ($m, @args) = @{$sql{$k}};
    @args == 2 and $args[0] =~ s/^\+//;
    $D->$m(@args, { self => $D, args => ["arg0"] });
}, sub {
    do_query_checks;
    do_cursor_checks;
    do_detail_checks;
    do_action_checks;
};

done_testing;
