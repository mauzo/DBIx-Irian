package DBIx::Irian::QuerySet;

use warnings;
use strict;

# properly speaking this ought to be a role

use DBIx::Irian           undef, qw(
    install_sub lookup load_class trace tracex
);
use DBIx::Irian::Cursor;

use Carp;

BEGIN {
    our @CLEAN = qw( carp croak register_query build_query );
}

sub _new { 
    my ($class, $db) = @_;
    bless \$db, $class;
}
sub _DB { ${$_[0]} }

sub register_query {
    my ($pkg, $name, $query) = @_;

    my $reg = lookup $pkg or croak "$pkg is not registered";
    $reg->{qs}{$name} and croak 
        "$pkg already has a query called '$name'";
    $reg->{qs}{$name} = $query;

    trace QRY => "[$pkg] [$name] [$query]";
}

sub build_query (&) {
    my ($cb) = @_;
    sub {
        my ($name, $row, $query) = @_;
        my $pkg = caller;
    
        if ($row) {
            $row = load_class $pkg, $row, "Row";
        }
        else {
            require DBIx::Irian::Row::Generic;
            $row = "DBIx::Irian::Row::Generic";
        }
        
        register_query $pkg, $name, $query;

        install_sub $pkg, $name, sub {
            my ($self, @args) = @_;
            my ($sql, @bind) = ref $query 
                ? $query->expand({
                    self    => $self,
                    row     => lookup($row),
                    args    => \@args,
                }) 
                : $query;

            my $DB = $self->_DB;
            $DB->dbc->run(sub { $cb->($sql, \@bind, $DB, $row) });
        };
    };
}

our %SUGAR = (
    # XXX these shouldn't really be here
    row_class => sub { 
        load_class scalar caller, $_[0], "Row" 
    },

    setup_row_class => sub {
        my ($row, @cols) = @_;
        my $pkg = caller;
        my $qcol = join ", ", map qq!"\Q$_\E"!, @cols;

        tracex { "[$row] [@cols]" } "GEN";

        # Make sure these are preloaded
        require PerlIO::scalar;
        require DBIx::Irian::Row;

        local @INC = sub {
            my ($self, $mod) = @_;
            trace GEN => "REQUIRE: [$mod]";
            s!/!::!g, s/\.pm$// for $mod;
            my $code = <<MOD;
package $mod;
use DBIx::Irian "Row";
columns $qcol;
1;
MOD

            trace GEN => "MOD: [$code]";
            open my $MOD, "<", \$code;
            return $MOD;
        };

        load_class $pkg, $row, "Row";
    },

    queryset => sub {
        my ($name, $qs) = @_;
        my $pkg = caller;
        my $class = load_class $pkg, $qs, "QuerySet";
        install_sub $pkg, $name, sub {
            $class->_new($_[0]->_DB)
        };
    },

    query => build_query {
        my ($sql, $bind, $DB, $row) = @_;

        tracex { "[$sql] [@$bind]" } "SQL";
        my $sth = $_->prepare($sql);
        $sth->execute(@$bind) or return;

        my $cols = $sth->{NAME};
        my $rows = $sth->fetchall_arrayref;
        $rows and @$rows or return;

        wantarray and return map $row->_new($DB, $_, $cols), @$rows;

        @$rows == 1 or carp "Query [$sql] returned more than one row";
        $row->_new($DB, $rows->[0], $cols);
    },

    # XXX mess
    detail => sub {
        my ($name, $query) = @_;
        my $pkg = caller;

        register_query $pkg, $name, $query;

        install_sub $pkg, $name, sub {
            my ($self, @args) = @_;
            my ($sql, @bind) = ref $query 
                ? $query->expand({
                    self    => $self,
                    args    => \@args,
                }) 
                : $query;

            my $DB = $self->_DB;
            $DB->dbc->run(sub {
                tracex { "[$sql] [@bind]" } "SQL";
                my $rows = $_->selectcol_arrayref($sql, undef, @bind);

                $rows and @$rows or return;
                wantarray and return @$rows;

                @$rows == 1 or carp "Query [$sql] returned more than one row";
                $rows->[0];
            });
        };
    },

    cursor => build_query {
        my ($sql, $bind, $DB, $row) = @_;

        DBIx::Irian::Cursor->new(
            dbh     => $_,
            DB      => $DB,
            sql     => $sql,
            bind    => $bind,
            row     => $row,
        );
    },

    action => sub {
        my ($name, $query) = @_;
        my $pkg = caller;

        register_query $pkg, $name, $query;

        install_sub $pkg, $name, sub {
            my ($self, @args) = @_;
            my ($sql, @bind) = ref $query 
                ? $query->expand({
                    self    => $self,
                    args    => \@args,
                }) 
                : $query;

            my $DB = $self->_DB;
            $DB->dbc->run(sub {
                tracex { "[$sql] [@bind]" } "SQL";
                $_->do($sql, undef, @bind);
            });
        };
    },
);

1;
