package DBIx::Irian::Inflate::ISBN;

use DBIx::Irian "Inflate";
use Business::ISBN;

sub inflate { Business::ISBN->new($_[1]) }
sub deflate { $_[1]->isbn }

1;
