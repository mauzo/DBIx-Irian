package t::Util::Subproc;

use 5.010;
use warnings;
use strict;

use Exporter "import";
our @EXPORT = qw/subproc/;

use IO::Handle;
use POSIX;
use TAP::Parser;
use Test::Builder;

sub do_child {
    my ($OUT, $cb) = @_;
    my $TB = Test::Builder->new;

    $TB->output($OUT);
    $TB->failure_output($OUT);
    $TB->todo_output($OUT);

    $cb->();

    $TB->done_testing;
    IO::Handle::flush $OUT;
    POSIX::_exit 0;
}

sub handle_test {
    my ($TB, $r) = @_;

    $TB->in_todo and $TB->todo_end;

    (my $nm = $r->description) =~ s/^- //;;
    my $why = $r->explanation;

    if ($r->has_skip) {
        $TB->skip($why);
        return;
    }
    
    $r->has_todo and $TB->todo_start($why);

    my $chan = $TB->in_todo ? "todo_output" : "failure_output";
    my $diag = $TB->$chan;
    $TB->$chan(\my $tmp);

    $TB->ok($r->is_actual_ok, $nm);

    $TB->$chan($diag);
}

sub run_parser {
    my ($TAP) = @_;
    my $TB = Test::Builder->new;

    my $P = TAP::Parser->new({source => $TAP});
    my $planned;
    while (my $r = $P->next) {
        given ($r->type) {
            when ("test") {
                handle_test $TB, $r;
            }
            when ("comment") { 
                (my $c = $r->raw) =~ s/^# //;
                $TB->diag($c);
            }
            when ("plan") {
                $planned = $r->tests_planned;
                last;
            }
        }
    }

    $TB->is_num($planned, $TB->current_test, "subproc finished tests OK");
}

sub subproc (&) {
    my ($cb) = @_;

    pipe my $TAP, my $OUT;

    my $pid = fork;
    defined $pid or die "can't fork: $!";

    unless ($pid) {
        close $TAP;
        do_child $OUT, $cb;
    }

    close $OUT;
    run_parser $TAP;

    waitpid $pid, 0;
    Test::Builder->new->is_num($?, 0, "subproc finished OK");
}

