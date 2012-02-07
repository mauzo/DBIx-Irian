package Prospect::DB;

use BSD::Process;

my $BSDP;
BEGIN { $BSDP = BSD::Process->new }
sub showmem { 
    $BSDP->refresh;
    my $rss = $BSDP->rssize;
    my $size = 4 * ($BSDP->tsize + $BSDP->dsize + $BSDP->ssize);
    warn "RES: $rss; SIZE: $size ($_[0])\n";
}
END { showmem "END" }

BEGIN { showmem "BEFORE DBIx::OQM" }
use DBIx::OQM "DB";

query book => Book => <<SQL;
    SELECT $Cols FROM book WHERE isbn = $Arg[0]
SQL

cursor books => Book => "SELECT $Cols FROM book";

1;
