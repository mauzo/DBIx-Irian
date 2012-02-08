package DBIx::OQM::Cursor;

use warnings;
use strict;

use Carp;
use DBIx::OQM   undef, qw/install_sub/;

use overload
    q/<>/   => "next",
    fallback => 1;

for my $n (qw/DB sql bind row cursor batch/) {
    install_sub $n, sub { $_[0]{$n} };
}

sub new {
    my ($class, %attr) = @_;
    my $self = bless \%attr, $class;
    $self->{cursor} = $self->DB->driver->cursor(
        $self->sql, $self->bind
    );
    $self->{rows} = [];
    $self->{batch} ||= 20;
    $self;
}

sub next {
    my ($self) = @_;
    my $rs = $self->{rows};
    @$rs or $rs = $self->{rows} = 
        $self->DB->driver->fetch($self->cursor, $self->batch)
        or return;
    $self->row->_new($self->DB, shift @$rs);
}

sub DESTROY {
    my ($self) = @_;
    $self->DB->driver->close($self->cursor);
}

1;
