package DBIx::Irian::PLPerl;

=head1 NAME

DBIx::Irian::PLPerl - Calling Irian from SQL with Postgres

=head1 SYNOPSIS

=head1 DESCRIPTION

PostgreSQL has for a long time supported writing database stored
procedures in Perl, using a Postgres extension called PL/Perl. Postgres
version 9 improved PL/Perl to the point where it is possible (with a
little administrator assistance) to use ordinary Perl modules from
stored procedures. This module is an experimental attempt to use these
facilities to map Irian objects and methods to SQL types and functions,
so that Irian can be used within SQL queries.

This interface is B<ALPHA>. It is liable to change significantly if I
find a better way of doing things. If you are using it for anything, I
recommend you let me know so I can discuss any changes with you.

=cut

use DBIx::Irian undef, qw/trace tracex lookup/;

use Exporter "import";
our @EXPORT = qw/ InstallDB /;

use Data::Dump  qw/pp/;
use Tie::OneOff;

use subs qw/
    write_row_type write_method
    write_db_setup
/;

sub InstallDB {
    my ($db) = @_ ? @_ : @ARGV;

    my %Class;
    {
        local %DBIx::Irian::Callback = (
            subclass => sub {
                my ($class, $kind) = @_;
                $Class{$class} = {
                    name    => $class,
                    kind    => $kind,
                };
            },

            extends => sub {
                my ($class, $extends) = @_;
                $Class{$class}{extends} = $extends;
            },

            query => sub {
                my ($class, $meth, $type, $args) = @_;
                $Class{$class}{method}{$meth} = {
                    name    => $meth,
                    kind    => $type,
                    (@$args == 2 ? (row => $$args[0]) : ()),
                };
            },

            method => sub {
                my ($class, $meth) = @_;
                $Class{$class}{method}{$meth} = {
                    name    => $meth,
                    kind    => "method",
                };
            },
        );

        DBIx::Irian::load_module $db;
    }

    #say pp \%Class;

    my (@setup, @types, @methods);

    push @setup, write_db_setup $db;

    for my $class (values %Class) {
        $$class{kind} eq "Row" or next;
        $$class{type}   = $$class{name} =~ s/^$db\:://r;
        $$class{cols}   = lookup $$class{name}, "cols";

        push @types, write_row_type $class;

        for my $meth (
            map values %{ $$_{method} },
            map $Class{$_},
            $$class{name}, @{ $$class{extends} }
        ) {
            $$meth{kind} eq "method" or next;
            push @methods, write_method $db, $class, $meth;
        }
    }

    print @setup, @types, @methods, "COMMIT;";
}

tie my %Q, "Tie::OneOff", sub {
    my ($v) = @_;
    $v =~ s/"/""/g;
    qq/"$v"/;
};
tie my %QQ, "Tie::OneOff", sub { qq/"\Q$_[0]\E"/ };
tie my %DB, "Tie::OneOff", sub {
    my ($db) = @_;
    qq/\$_SHARED{"DBIx::Irian::PLPerl"}{DB}{"\Q$db\E"}/;
};

sub write_row_type {
    my ($info) = @_;

    my $as = join ", ", map "$Q{$_} text", @{$$info{cols}};

    <<SQL;
create type $Q{$$info{type}} as ($as);
SQL
}

sub write_method {
    my ($db, $class, $meth) = @_;

    my ($row, $type)    = @$class{qw/name type/};
    my $name            = $$meth{name};
    trace PLP => "METHOD [$row] [$type] [$name]";

    my $cols = join ", ", map $QQ{$_}, @{$$class{cols}};

    <<SQL;
create function $Q{$name} ($Q{$type})
    returns text
    language plperl
    as \$\$
        my \$m = $QQ{$name};
        scalar $QQ{$row}->_new(
            $DB{$db},
            [\@{\$_[0]}{$cols}],
            [$cols],
        )->\$m;
    \$\$;
SQL
}

sub write_db_setup {
    my ($db) = @_;
    <<SQL;
create function $Q{"setup_$db"} ()
    returns void
    language plperl
    as \$\$
        require $db;
        $DB{$db} = $QQ{$db}\->new("dbi:PgSPI:");
    \$\$;
SQL
}

1;
