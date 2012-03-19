package DBIx::Irian::DB;

use warnings;
use strict;

use parent "DBIx::Irian::QuerySet";

use DBIx::Irian         undef, qw(
    install_sub tracex expand_query
);
use DBIx::Connector;
use DBIx::Irian::Driver;
use Scalar::Util        qw/reftype/;
use Carp                qw/carp/;

BEGIN { our @CLEAN = qw/reftype carp/ }

push @Data::Dump::FILTERS, sub {
    my ($ctx, $obj) = @_;
    $ctx->object_isa(__PACKAGE__) or return;
    my %hv = %{$obj};
    delete @hv{qw/dbc dbh _DB driver/};
    { dump => $ctx->class . "->new(" . Data::Dump::pp(\%hv) . ")" };
};

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

sub do_expand_query {
    my ($self, $row, $query, $args) = @_;
    $args = 
        ref $args ?
            reftype $args eq "ARRAY"    ? $args         :
            reftype $args eq "HASH"     ? [ %$args ]    :
            croak("Bad reftype '$args'")                :
        [];
    tracex {
        require Data::Dump;
        "DO EXPAND [$row][$query] " . Data::Dump::pp({@$args});
    } "EXP";
    expand_query $query, {
        @$args,
        db  => $self,
        row => $row,
    };
}

sub do_query {
    my ($self, $row, $query, $args) = @_;
    my ($sql, @bind) = $self->do_expand_query($row, $query, $args);

    my ($cols, $rows) = $self->dbc->run(sub {
        tracex { "[$sql] [@bind]" } "SQL";

        my $sth = $_->prepare($sql);
        $sth->execute(@bind) or return;

        ($sth->{NAME}, $sth->fetchall_arrayref);
    });
    $rows and @$rows or return;

    wantarray and return map $row->_new($self, $_, $cols), @$rows;

    @$rows == 1 or carp "Query [$sql] returned more than one row";
    $row->_new($self, $rows->[0], $cols);
}

sub do_cursor {
    my ($self, $row, $query, $args) = @_;
    my ($sql, @bind) = $self->do_expand_query($row, $query, $args);

    DBIx::Irian::Cursor->new(
        DB      => $self,
        sql     => $sql,
        bind    => \@bind,
        row     => $row,
    );
}

sub do_detail {
    my ($self, $query, $args) = @_;
    my ($sql, @bind) = $self->do_expand_query(undef, $query, $args);

    my $rows = $self->dbc->run(sub {
        tracex { "[$sql] [@bind]" } "SQL";
        $_->selectcol_arrayref($sql, undef, @bind);
    });
    $rows or return;

    tracex { "DETAIL [@$rows]" } "ROW";
    @$rows or return;
    wantarray and return @$rows;

    @$rows == 1 or carp "Query [$sql] returned more than one row";
    $rows->[0];
}

sub do_action {
    my ($self, $query, $args) = @_;
    my ($sql, @bind) = $self->do_expand_query(undef, $query, $args);

    $self->dbc->run(sub {
        tracex { "[$sql] [@bind]" } "SQL";
        $_->do($sql, undef, @bind);
    });
}

1;
