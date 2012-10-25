package t::Util::DB;

use warnings;
use strict;

use Exporter "import";
our @EXPORT = qw/ setup_qs_methods /;

our %QS;
do "t/QS.pl";

sub setup_qs_methods {
    my $rv = qq{sub foo { "foo" }\n};
    for my $n (keys %QS) {
        my ($t, $sql) = @{$QS{$n}};
        my $r = $t eq "cursor" || $t eq "query"
            ? q{=> "+t::Row"} : "";
        $rv .= "$t $n $r => $sql;\n";
    }
    $rv;
}

1;
