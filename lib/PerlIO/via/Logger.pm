package PerlIO::via::Logger;

use 5.010;
use warnings;
use strict;

sub PUSHED {
    my ($class) = @_;
    bless [undef, ""], $class;
}

sub OPEN {
    my ($self, $conf) = @_;
    $self->[0] = $conf;
    return 1;
}

sub WRITE {
    my ($self, $buf) = @_;

    $self->[1] .= $buf;

    my $conf    = $self->[0];
    my $log     = $conf->{logger};
    my $level   = $conf->{level};
    my $prefix  = $conf->{prefix};
    my $rs      = $conf->{rs} // "\n";

    $prefix = length $prefix ? "$prefix: " : "";

    if (length $rs) {
        $log->$level("$prefix$1") 
            while $self->[1] =~ s/^(.*?)\Q$rs//s;
    }
    else {
        $log->$level("$prefix$$self[1]");
        $self->[1] = "";
    }

    return length $buf;
}

sub CLOSE { 0 }

1;
