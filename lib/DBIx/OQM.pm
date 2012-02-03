package DBIx::OQM;

use 5.010;
use warnings;
use strict;

our $VERSION = "1";

use Carp;
use DBIx::Connector;
use Tie::OneOff;
use Scalar::Util    qw/reftype/;
use Sub::Name       qw/subname/;
use List::MoreUtils qw/part/;

use DBIx::OQM::Defer;

our @EXPORT = qw/
    $Arg @Arg %Arg
    $Cols @Cols %Cols
    %Self
    columns query
/;

sub import {
    my ($from, $type) = @_;
    my $to = caller;
    strict->import;
    warnings->import;
    feature->import(":5.10");

    if ($type) {
        my $parent = "$from\::$type";
        unless ($to->isa($parent)) {
            eval "require $parent; 1" or croak $@;
            no strict "refs"; 
            @{"$to\::ISA"} = $parent;
        }
    }
  
    # always use the default export list
    $from->Exporter::export($to);
}

our (%P, %Q);

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

sub columns {
    my $pkg = caller;
    $P{$pkg}{db} or croak "$pkg is a cursor class, load the DB instead";
    $P{$pkg}{cols} = [ @_ ];
    for my $ix (0..$#_) {
        no strict "refs";
        *{"$pkg\::$_[$ix]"} = subname $_[$ix], sub { $_[0][$ix] };
    }
}

sub quote_identifier { shift; join ".", map qq/"$_"/, @_ }

sub expand {
    my ($str, $q) = @_;
    local *Q = $q;
    $Q{pkg} = $P{$Q{pkg}};
    $str->force, $str->bind;
}

sub qualify {
    my ($pkg, $base) = @_;
    $pkg =~ s/^\+// ? $pkg : "$base\::$pkg";
}

sub query { 
    my ($name, $cursor, $sql) = @_;
    my $pkg = caller;

    my $db = $P{$pkg}{db} ||= $pkg;
    $cursor = qualify $cursor, $db;

    unless ($P{$cursor}) {
        $P{$cursor}{db} = $db;
        eval "require $cursor; 1" or croak $@;
    }

    my $m = subname $name, sub {
        my ($self, @args) = @_;
        my ($sql, @bind) = expand $sql, {
            self    => $self,
            pkg     => $cursor,
            dbh     => __PACKAGE__,
            args    => \@args,
        };
        s/^\s+//, s/\s+$// for $sql;
        local $" = "][";
        warn "SQL: [$sql] [@bind] -> [$cursor]";
    };

    no strict "refs";
    *{"$pkg\::$name"} = $m;
}

1;
