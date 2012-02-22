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

our %UTILS = map +($_, __PACKAGE__->can($_)), qw(
    trace tracex
    install_sub find_sym qualify load_class
    register lookup
);

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
        eval "require $class; 1" or croak $@;
    }
    lookup($class, "type") eq $type or croak 
        "Not a $type class: $class";

    return $class;
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

# XXX this doesn't clean up
sub export_utils {
    my ($util, $to) = @_;
    eval "require $util; 1;" or croak $@;
    $util->Exporter::export($to);
}

sub setup_subclass {
    my ($class, $root, $type) = @_;

    register $class, type => $type;

    if ($type eq "DB") {    # XXX
        register $class, db => $class;
    }

    my $parent = "$root\::$type";
    eval "require $parent; 1" or croak $@;

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

        $c->Exporter::export($class);
    }

    export_utils $_, $class
        for map "DBIx::Irian::$_", qw/ Query Inflate /;

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

    my @clean;
    for my $n (@utils) {
        my $cv = $UTILS{$n} or croak 
            "$n is not exported by $from";
        install_sub $to, $n, $cv;
        push @clean, $n;
    }

    on_scope_end { 
        my $av = find_sym($to, '@CLEAN') || [];
        tracex { "CLEAN [$to]: [@$av]" } "SYM";
        uninstall_sub $to, $_ for @clean, @$av;
    };
}

1;
