use t::Util;

BEGIN { $ENV{IRIAN_TRACE} = "ONE,THREE" }
use DBIx::Irian undef, qw/trace tracex/;

sub check_trace {
    my ($want, $name) = @_;
    
    my @rv;
    local $SIG{__WARN__} = sub { push @rv, $_[0] };

    trace ONE => "one";
    trace TWO => "two";
    trace THREE => "three";
    chop @rv;
    is_deeply \@rv, $want,          "trace $name";

    @rv = ();
    tracex { "one" } "ONE";
    tracex { "two" } "TWO";
    tracex { "three" } "THREE";
    chop @rv;
    is_deeply \@rv, $want,          "tracex $name";
}

check_trace ["ONE: one", "THREE: three"],   "honours \$ENV{IRIAN_TRACE}";

DBIx::Irian::set_trace_flags TWO => 1;
check_trace ["ONE: one", "TWO: two", "THREE: three"],
                                        "allows flags to be switched on";

DBIx::Irian::set_trace_flags THREE => 0;
check_trace ["ONE: one", "TWO: two"],   "allows flags to be switched off";

DBIx::Irian::set_trace_to sub { warn uc "$_[0]\n" };
check_trace ["ONE: ONE", "TWO: TWO"],   "allows trace to be redirected";

DBIx::Irian::set_trace_to undef;
check_trace ["ONE: one", "TWO: two"],   "allows trace to be put back";

done_testing;
