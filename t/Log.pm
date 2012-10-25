package t::Log;

use parent "Catalyst::Log";

my @log;

sub _send_to_log { 
    my ($self, @msgs) = @_;
    push @log, map split(/\n/), @msgs;
}

sub _fetch_from_log { 
    $_[0]->_flush;
    splice @log; 
}

1;
