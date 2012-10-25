package PerlIO::via::Logger;

=head1 NAME

PerlIO::via::Logger - Redirect IO to a logger object

=cut

use 5.010;
use warnings;
use strict;

=head1 SYNOPSIS

    open my $LOG, ">:via(Logger)", {
        logger  => $logger,
        level   => "debug",
        prefix  => "DBI",
    };

    DBI->trace(DBI->trace, $LOG);

=head1 DESCRIPTION

This is a PerlIO layer which redirects all IO to a log object. As the
synopsis shows, it is intended for redirecting L<DBI>'s trace output,
but it's general enough to be useful in other situations.

To create a filehandle C<$FH> which logs messages by calling the
C<debug> method of a logging object C<$log>, use 3-arg C<open> like
this:

    open my $FH, ">:via(Logger)", {
        logger  => $log,
        level   => "debug",
    };

The filehandle should be opened for writing; it may be opened
read/write, but reads will always return EOF. Do not attempt to push
this layer onto an existing filehandle with C<binmode>, since there is
no way to pass in the configuration. Other layers (C<:encoding>, say)
may be pushed on top, but since this layer will never pass data down
there is no point including layers underneath.

Configuration is via a hashref passed to C<open> in place of a filename.
The following keys are recognised.

=over 4

=item C<logger>

The log object to use. Required.

=item C<level>

A string naming the method to call on the log object for each log entry.
Required.

=item C<prefix>

A string to prefix to each log entry before passing it off to the
logger. If this string is non-empty a colon and a space will be inserted
between the prefix and the message. Optional, defaults to the empty
string.

=item C<rs>

The string separating log entries. Since the upward interface is a
filehandle, it's likely that calling code may split a single entry
across several writes, or write several entries at once. This allows us
to separate them out again to feed to the log object. 

If this is the empty string, each call to C<WRITE> will be written as a
single log entry.

Optional, defaults to C<"\n">.

=back

=cut

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

=head1 AUTHOR

Ben Morrow <ben@morrow.me.uk>

=head1 BUGS

Currently this module is distributed as part of L<DBIx::Irian>, so
please report bugs to <bug-DBIx-Irian@rt.cpan.org>.

=head1 COPYRIGHT

Copyright 2012 Ben Morrow.

Released under the 2-clause BSD license.

