package DBIx::Irian::Cursor;

use warnings;
use strict;

use Carp;
use DBIx::Irian   undef, qw/install_sub/;

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

sub _rows {
    my ($self) = @_;
    my $rs = $self->{rows};
    @$rs or $rs = $self->{rows} = 
        $self->DB->driver->fetch($self->cursor, $self->batch)
        or return;
    return $rs;
}

sub next {
    my ($self) = @_;
    my $rs = $self->_rows or return;
    $self->row->_new($self->DB, shift @$rs);
}

sub peek {
    my ($self) = @_;
    my $rs = $self->_rows or return;
    $self->row->_new($self->DB, @$rs);
}

sub all {
    my ($self) = @_;
    my ($db, $row, $curs, $n) = map $self->$_, 
        qw/DB row cursor batch/;

    my @rv  = map $row->_new($db, $_), @{delete $self->{rows}};

    # I realise we're necessarily eating memory at this point, but try
    # to avoid doing so more than we have to.
    while (my $rs = $db->driver->fetch($curs, $n)) {
        push @rv, map $row->_new($db, $_), @$rs;
    }

    return @rv;
}

sub DESTROY {
    my ($self) = @_;
    my $c = $self->cursor;
    $c and $self->DB->driver->close($c);
}

1;
