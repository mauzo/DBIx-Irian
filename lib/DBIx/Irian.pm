package DBIx::Irian;

use 5.010;
use warnings;
use strict;
use mro;

our $VERSION = "1";

use Carp;
use Sub::Name               qw/subname/;
use B::Hooks::EndOfScope;
use B::Hooks::AtRuntime;
use Scope::Upper            qw/reap CALLER/;

# The bootstrapping order is rather specific. Currently that means the
# exports for this module are buried halfway down the file, in a call to
# register_utils. Probably Trace, Sym, and Util should go into their own
# modules.

{
    my $TraceLog = sub { warn "$_[0]\n" };
    my %TraceFlags;

    sub trace {
        my ($level, $msg) = @_;
        $TraceFlags{$level} and $TraceLog->("$level: $msg");
    }

    sub tracex (&$) {
        my ($cb, $level) = @_;
        if ($TraceFlags{$level}) {
            trace $level, $_ for do {
                local $" = "][";
                # We can't 'no warnings uninitiailisizied' $cb, so just
                # swallow all warnings.
                local $SIG{__WARN__} = sub {};
                $cb->();
            };
        }
    }

    sub set_trace_flags {
        my (%f) = @_;
        $TraceFlags{$_} = $f{$_} for keys %f;
    }

    sub set_trace_to { $TraceLog = $_[0] }

    if (exists $ENV{IRIAN_TRACE}) {
        set_trace_flags map +($_, 1), split /,/, $ENV{IRIAN_TRACE};
    }
}

{
    my %sigs = (
        '$' => "SCALAR",
        '@' => "ARRAY",
        '%' => "HASH",
        '&' => "CODE",
        '*' => "GLOB",
    );

    sub find_sym {
        my ($pkg, $sym) = @_;
        no warnings "once";

        if ($sym eq "::") {
            no strict "refs";
            return \%{"$pkg\::"};
        }

        my ($sig, $name) = $sym =~ /(.)(.*)/;
        my $gv = do {
            no strict "refs";
            \*{"$pkg\::$name"};
        };
        return *$gv{$sigs{$sig}};
    }
}

sub install_sub {
    my $pkg = @_ > 2 ? shift : caller;
    my ($n, $cv) = @_;
    trace SYM => "INSTALLING [$cv] AS [$n] IN [$pkg]";
    my $gv = find_sym $pkg, "*$n";
    *$gv = subname "$pkg\::$n", $cv;
}

sub uninstall_sub {
    my ($from, $n) = @_;
    trace SYM => "REMOVING [$n] FROM [$from]";

    my $old = find_sym $from, "*$n";
    my $hv  = find_sym $from, "::";
    delete $hv->{$n};

    my $new = find_sym $from, "*$n";
    *$old{SCALAR}   and *$new = *$old{SCALAR};
    *$old{ARRAY}    and *$new = *$old{ARRAY};
    *$old{HASH}     and *$new = *$old{HASH};
    *$old{IO}       and *$new = *$old{IO};
    # skip FORMAT since it's buggy in some perls
}

{
    our %Utils;

    sub register_utils {
        my $pkg = caller;
        my @u = @_;
        for (@u) {
            $Utils{$_} and croak "Util [$_] already registered";
            $Utils{$_} = $pkg->can($_);
        }
        tracex { "REG [$pkg] [@u]" } "UTL";
    }

    sub export_utils {
        my ($to, @utils) = @_;
        
        tracex { "EXPORT [$to] [@utils]" } "UTL";
        for my $n (@utils) {
            my $cv = $Utils{$n} or croak 
                "$n is not exported by DBIx::Irian";
            install_sub $to, $n, $cv;
        }

        on_scope_end { uninstall_sub $to, $_ for @utils };
    }
}

register_utils qw(
    trace tracex
    register_utils
    install_sub find_sym qualify load_class
    register lookup
    expand_query
);

require DBIx::Irian::Query;
require DBIx::Irian::Inflate;

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

        tracex {
            require Data::Dump;
            sprintf "[$pkg] => %s",
                Data::Dump::dump $hv;
        } "REG";
    }

    sub lookup { 
        my $hv = $Pkg{$_[0]};
        @_ > 1 ? $hv->{$_[1]} : $hv;
    }
}

sub load_module { eval "require $_[0]; 1;" or croak $@; $_[0] }

sub qualify {
    my ($pkg, $base) = @_;
    $pkg =~ s/^\+// ? $pkg : "$base\::$pkg";
}

sub load_class {
    my ($pkg, $sub, $type) = @_;

    my $db = lookup $pkg, "db"
        or croak "Can't find DB class for '$pkg'";
    trace REG => "DB [$db] FOR [$pkg]";
    my $class = qualify $sub, $db;

    unless (lookup $class) {
        # we have to do this before loading the Row class, otherwise
        # queries in that Row class won't know which DB they are in
        register $class, db => $db;
        load_module $class;
    }
    lookup($class, "type") eq $type or croak 
        "Not a $type class: $class";

    return $class;
}

sub expand_query {
    my ($query, $args) = @_;

    my ($sql, @bind) = ref $query 
        ? $query->expand($args)
        : $query;

    wantarray or return $sql;
    return $sql, @bind;
}

sub setup_isa {
    my ($class, $type) = @_;
    trace ISA => "SETUP [$class] [$type]";

    my $isa = find_sym $class, '@ISA';
    my $extends = lookup $class, "extends";

    $extends            and push @$isa, @$extends;
    $class->isa($type)  or push @$isa, $type;

    tracex { "[$class]: [@$isa]" } "ISA";
}

sub setup_subclass {
    my ($class, $root, $type) = @_;

    register $class, type => $type;

    if ($type eq "DB") {    # XXX
        register $class, db => $class;
    }

    my $parent = "$root\::$type";
    load_module $parent;

    at_runtime {
        reap sub {
            setup_isa $class, $parent;

            tracex { 
                my $mro = mro::get_linear_isa $class;
                "MRO [$class] [@$mro]" 
            } "ISA";

        }, CALLER(2);
        # CALLER(2) since at_runtime adds an extra stack frame for
        # BHAR::run
    };
    
    my @clean;
    my $mro = mro::get_linear_isa $parent;
    for my $c (@$mro) {
        my $sugar = find_sym $c, '%SUGAR';
        while (my ($n, $cv) = each %$sugar) {
            install_sub $class, $n, $cv;
            push @clean, $n;
        }

        # XXX I don't think this is useful
        $c->Exporter::export($class);
    }

    # This should only export variables.
    DBIx::Irian::Query->Exporter::export($class);

    on_scope_end {
        uninstall_sub $class, $_ for @clean;
    };
}

sub import {
    my ($from, $type, @utils) = @_;
    my $to = caller;
    strict->import;
    warnings->import;
    feature->import(":5.10");

    $type and setup_subclass $to, $from, $type;

    export_utils $to, @utils;

    on_scope_end { 
        my $av = find_sym($to, '@CLEAN') || [];
        tracex { "CLEAN [$to]: [@$av]" } "SYM";
        uninstall_sub $to, $_ for @$av;
    };
}

1;
