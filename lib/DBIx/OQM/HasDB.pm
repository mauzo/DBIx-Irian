package DBIx::OQM::HasDB;

use warnings;
use strict;

# properly speaking this ought to be a role

use DBIx::OQM           undef, qw/install_sub lookup register/;
use DBIx::OQM::Defer;
use DBIx::OQM::Cursor;

use Carp;
use Tie::OneOff;

sub _DB { $_[0]{_DB} }

our %Q;

tie our @Arg, "Tie::OneOff",
    FETCH => sub { my ($k) = @_; placeholder { $Q{args}[$k] }; },
    FETCHSIZE => sub { undef };
tie our %Arg, "Tie::OneOff", sub {
    my ($k) = @_;
    placeholder { 
        my $hv = $Q{arghv} ||= { @{$Q{args}} };
        $hv->{$k};
    };
};

our $Cols = defer { 
    join ", ", 
        map $Q{dbh}->quote_identifier($_), 
        @{$Q{pkg}{cols}};
};
tie our @Cols, "Tie::OneOff",
    FETCH =>        sub { $Q{pkg}{cols}[$_[0]] },
    FETCHSIZE =>    sub { scalar @{$Q{pkg}{cols}} };
tie our %Cols, "Tie::OneOff", sub {
    my ($k) = @_;
    defer {
        join ", ",
            map $Q{dbh}->quote_identifier($k, $_),
            @{$Q{pkg}{cols}};
    };
};

tie our %Self, "Tie::OneOff", sub {
    my ($k) = @_;
    placeholder { $Q{self}->$k };
};

our @EXPORT = qw(
    @Arg %Arg @Cols $Cols %Cols %Self
);

sub expand {
    my ($str, $q) = @_;
    local *Q = $q;
    $str->force, $str->bind;
}

sub qualify {
    my ($pkg, $base) = @_;
    $pkg =~ s/^\+// ? $pkg : "$base\::$pkg";
}

our %SUGAR = (
    query => sub { 
        my ($name, $row, $sql) = @_;
        my $pkg = caller;

        my $db = lookup $pkg, "db";
        warn "DB [$db] FOR [$pkg]\n";
        $row = qualify $row, $db;

        unless (lookup $row) {
            register $row, db => $db;
            eval "require $row; 1" or croak $@;
        }

        install_sub $pkg, $name, sub {
            my ($self, @args) = @_;
            my ($sql, @bind) = expand $sql, {
                self    => $self,
                pkg     => lookup($row),
                dbh     => $self->_DB->dbh,
                args    => \@args,
            };
            s/^\s+//, s/\s+$// for $sql;
            local $" = "][";
            warn "SQL: [$sql] [@bind] -> [$row]\n";

            my $DB = $self->_DB;
            $DB->dbc->run(sub {
                my $sth = $_->prepare($sql);
                $sth->execute(@bind);
                bless {
                    sth     => $sth,
                    _DB     => $DB,
                    row     => $row,
                }, "DBIx::OQM::Cursor";
            });
        };
    },
);

1;
