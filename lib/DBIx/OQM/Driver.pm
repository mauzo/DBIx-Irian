package DBIx::OQM::Driver;

use warnings;
use strict;

use DBIx::OQM   undef, qw/install_sub/;

for my $n (qw/dbc/) {
    install_sub $n, sub { $_[0]{$n} };
}

sub dbh { $_[0]->dbc->dbh }

sub new {
    my ($class, $dbc) = @_;

    my $dbh = $dbc->dbh;
    my $subclass = "$class\::$$dbh{Driver}{Name}";
    warn "TRYING [$subclass]\n";
    eval "require $subclass; 1;"
        and $subclass->isa($class)
        and $class = $subclass;

    warn "USING [$class]\n";
    my $self = bless { dbc => $dbc }, $class;
    $self->init;
    $self;
}

sub init { }

sub query_all {
    my ($self, $sql, $bind) = @_;
    $self->dbh->selectall_arrayref($sql, undef, @$bind);
}

sub query_one {
    my ($self, $sql, $bind) = @_;
    $self->dbh->selectrow_arrayref($sql, undef, @$bind);
}

sub cursor {
    my ($self, $sql, $bind) = @_;
    $self->query_all($sql, $bind);
}

sub fetch {
    my ($self, $cursor, $n) = @_;
    warn "BATCH: " . scalar @$cursor;
    @$cursor or return;
    [splice @$cursor, 0, $n];
}

sub close { @{$_[1]} = () }

1;
