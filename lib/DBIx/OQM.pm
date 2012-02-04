package DBIx::OQM;

use 5.010;
use warnings;
use strict;
use mro;

our $VERSION = "1";

use Carp;
use B::Hooks::EndOfScope;
use Sub::Name               qw/subname/;

use DBIx::OQM::Defer;

our %UTILS = map +($_, __PACKAGE__->can($_)), qw(
    install_sub register lookup
);

sub install_sub {
    my $pkg = @_ > 2 ? shift : caller;
    my ($n, $cv) = @_;
    warn "INSTALLING [$cv] AS [$n] IN [$pkg]\n";
    no strict "refs";
    *{"$pkg\::$n"} = subname $n, $cv;
}

sub uninstall_sub {
    my ($from, $n) = @_;
    warn "REMOVING [$n] FROM [$from]\n";

    no strict "refs";
    my $old = \*{"$from\::$n"};
    delete ${"$from\::"}{$n};

    my $new = \*{"$from\::$n"};
    *$old{SCALAR}   and *$new = *$old{SCALAR};
    *$old{ARRAY}    and *$new = *$old{ARRAY};
    *$old{HASH}     and *$new = *$old{HASH};
    *$old{IO}       and *$new = *$old{IO};
    # skip FORMAT since it's buggy in some perls
}

{
    my %Pkg;

    sub register {
        my ($pkg, %props) = @_;
        my $hv = $Pkg{$pkg} ||= { pkg => $pkg };

        for (keys %props) {
            exists $hv->{$_} and croak
                "[$pkg] already has [$_] => [$$hv{$_}]";
            $hv->{$_} = $props{$_};
        }

        use Data::Dump;
        warn sprintf "REG: [$pkg] => %s\n",
            Data::Dump::dump $hv
    }

    sub lookup { 
        my $hv = $Pkg{$_[0]};
        @_ > 1 ? $hv->{$_[1]} : $hv;
    }
}

sub setup_subclass {
    my ($class, $root, $type) = @_;

    if ($type eq "DB") {    # XXX
        register $class,
            db      => $class,
            type    => "db";
    }
    
    my $parent = "$root\::$type";
    unless ($class->isa($parent)) {
        eval "require $parent; 1" or croak $@;
        no strict "refs"; 
        @{"$class\::ISA"} = $parent;
    }

    my @clean;
    my $mro = mro::get_linear_isa $parent;
    for my $c (@$mro) {
        my $sugar = do {
            no strict "refs";
            no warnings "once";
            \%{"$c\::SUGAR"}
        };
        while (my ($n, $cv) = each %$sugar) {
            install_sub $class, $n, $cv;
            push @clean, $n;
        }

        $c->Exporter::export($class);
    }

    return @clean;
}

sub import {
    my ($from, $type, @utils) = @_;
    my $to = caller;
    strict->import;
    warnings->import;
    feature->import(":5.10");

    warn "IMPORT: [$from] FOR [$to]\n";

    my @clean;
    $type and push @clean, setup_subclass $to, $from, $type;
    
    local $" = "][";
    warn "UTILS FOR [$to]: [@utils]\n";
    for my $n (@utils) {
        my $cv = $UTILS{$n} or croak 
            "$n is not exported by $from";
        install_sub $to, $n, $cv;
        push @clean, $n;
    }

    on_scope_end { uninstall_sub $to, $_ for @clean };
}

1;
