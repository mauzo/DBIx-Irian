package DBIx::OQM::DB;

use warnings;
use strict;

use parent "DBIx::OQM::HasDB";

use DBIx::OQM       undef, qw/install_sub/;
use DBIx::Connector;
use DBIx::OQM::Driver;

for my $n (qw/dbc dsn user password driver _DB/) {
    install_sub $n, sub { $_[0]{$n} };
}

for my $n (qw/dbh txn svp/) {
    install_sub $n, sub {
        my ($self, @args) = @_;
        $self->dbc->$n(@args);
    };
}

sub new {
    my ($class, @args) = @_;
    my %self = @args == 1 ? (dsn => @args) : @args;

    $self{dbi}  ||= {
        RaiseError  => 1,
        AutoCommit  => 1,
    };
    $self{dbc}  ||= DBIx::Connector->new(
        @self{qw/dsn user password dbi/}
    );
    $self{driver}   ||= DBIx::OQM::Driver->new($self{dbc});

    $self{_DB} = bless \%self, $class;
}

1;
