package DBIx::Irian::QuerySet;

use warnings;
use strict;

# properly speaking this ought to be a role

use DBIx::Irian           undef, qw(
    install_sub lookup load_class trace tracex
);
use DBIx::Irian::Cursor;

use Carp;

BEGIN { our @CLEAN = qw( 
    carp croak 
    register_query install_db_method build_query build_row_query
) }

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

    trace QRY => "QUERY [$pkg][$name]: [$query]";
}

sub install_db_method {
    my ($pkg, $name, $method, $margs, $xargs) = @_;

    trace QRY => "DB METHOD [$pkg][$name]: [$method]";

    install_sub $pkg, $name, sub {
        my ($self, @args) = @_;
    
        trace QRY => "CALL [$method] [$pkg][$name]";

        my $DB = $self->_DB;
        $DB->$method(@$margs, { 
            @$xargs,
            self    => $self,
            args    => \@args,
            db      => $DB,
        });
    };
}

sub build_query {
    my ($method) = @_;
    sub {
        my ($name, $query) = @_;
        my $pkg = caller;

        register_query $pkg, $name, $query;
        install_db_method $pkg, $name, $method,
            [$query], [];
    };
}

sub build_row_query {
    my ($method) = @_;
    sub {
        my ($name, $row, $query) = @_;
        my $pkg = caller;

        my ($class, $reg);
        if ($row) {
            $class = load_class $pkg, $row, "Row";
            $reg = lookup $class;
        }
        else {
            require DBIx::Irian::Row::Generic;
            $class = "DBIx::Irian::Row::Generic";
        }

        register_query $pkg, $name, $query;
        install_db_method $pkg, $name, $method,
            [$class, $query], [ row => $reg ];

        trace QRY => "ROW [$pkg][$name]: [$class]";
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

    query   => build_row_query("do_query"),
    cursor  => build_row_query("do_cursor"),
    detail  => build_query("do_detail"),
    action  => build_query("do_action"),
);

1;
