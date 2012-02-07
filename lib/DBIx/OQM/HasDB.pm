package DBIx::OQM::HasDB;

use warnings;
use strict;

# properly speaking this ought to be a role

use DBIx::OQM           undef, qw/install_sub lookup register/;
use DBIx::OQM::Cursor;

use Carp;

sub _DB { $_[0]{_DB} }

BEGIN {
    our @CLEAN = qw( qualify row_class );
}

sub qualify {
    my ($pkg, $base) = @_;
    $pkg =~ s/^\+// ? $pkg : "$base\::$pkg";
}

sub row_class {
    my ($pkg, $row) = @_;

    my $db = lookup $pkg, "db";
    warn "DB [$db] FOR [$pkg]\n";
    $row = qualify $row, $db;

    unless (lookup $row) {
        # we have to do this before loading the Row class, otherwise
        # queries in that Row class won't know which DB they are in
        register $row, db => $db;
        eval "require $row; 1" or croak $@;
    }

    return $row;
}

sub build_query (&) {
    my ($cb) = @_;
    sub {
        my ($name, $row, $query) = @_;
        my $pkg = caller;

        $row = row_class $pkg, $row;

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
