package DBIx::Irian::DB;

use warnings;
use strict;

use parent "DBIx::Irian::QuerySet";

use DBIx::Irian         undef, qw/install_sub/;
use DBIx::Connector;
use DBIx::Irian::Driver;
use Scalar::Util        qw/reftype/;

BEGIN { our @CLEAN = qw/reftype/ }

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
    my %self = @args == 1 
        ? ref $args[0]
            ? %{$args[0]}
            : (dsn => @args) 
        : @args;

    $self{dbi}      ||= {
        RaiseError  => 1,
        AutoCommit  => 1,
    };
    $self{dbc}      ||= DBIx::Connector->new(
        @self{qw/dsn user password dbi/}
    );
    $self{driver}   ||= DBIx::Irian::Driver->new($self{dbc});

    exists $self{mode} and $self{dbc}->mode($self{mode});

    $self{_DB} = bless \%self, $class;
}

1;
