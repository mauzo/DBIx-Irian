package DBIx::OQM::HasDB;

use warnings;
use strict;

# properly speaking this ought to be a role

use DBIx::OQM           undef, qw/install_sub lookup row_class/;
use DBIx::OQM::Cursor;

use Carp;

BEGIN {
    our @CLEAN = qw( carp croak build_query );
}

sub _DB { $_[0]{_DB} }

sub build_query (&) {
    my ($cb) = @_;
    sub {
        my ($name, $row, $query) = @_;
        my $pkg = caller;

        $row = row_class $pkg, $row;

        my $reg = lookup $pkg
            or croak "$pkg is not registered";
        $reg->{qs}{$name} and croak 
            "$pkg already has a query called '$name'";
        $reg->{qs}{$name} = $query;

        install_sub $pkg, $name, sub {
            my ($self, @args) = @_;
            my ($sql, @bind) = ref $query 
                ? $query->expand(
                    self    => $self,
                    row     => lookup($row),
                    args    => \@args,
                ) 
                : $query;

            my $DB = $self->_DB;
            $DB->dbc->run(sub { $cb->($sql, \@bind, $DB, $row) });
        };
    };
}

our %SUGAR = (
    query => build_query {
        my ($sql, $bind, $DB, $row) = @_;

        local $" = "][";
        warn "SQL: [$sql] [@$bind]\n";
        my $rows = $_->selectall_arrayref($sql, undef, @$bind);
        $rows and @$rows or return;

        if (wantarray) {
            map $row->_new($DB, $_), @$rows;
        }
        else {
            @$rows == 1 or carp
                "Query [$sql] returned more than one row";
            $row->_new($DB, $rows->[0]);
        }
    },

    cursor => build_query {
        my ($sql, $bind, $DB, $row) = @_;

        DBIx::OQM::Cursor->new(
            dbh     => $_,
            DB      => $DB,
            sql     => $sql,
            bind    => $bind,
            row     => $row,
        );
    },
);

1;
