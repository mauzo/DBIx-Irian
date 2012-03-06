use t::Util;
use Data::Dump      "pp";

fakerequire pragmas => q{
    no strict;
    no warnings;
    use DBIx::Irian;

    BEGIN {
        ok $^H & strict::bits(qw/subs refs vars/),
                                    "use Irian implies strict";
        ok ${^WARNING_BITS} & warnings::bits,
                                    "use Irian implies warnings";
        for (qw/switch say state/) {
            ok $^H{"feature_$_"},   "use Irian implies feature '$_'";
        }
    }

    1;
};

my $Pkg;
our %CB;

sub irian_ok {
    my ($args, $vis, $invis, $name) = @_;
    $Pkg = new_import_pkg;
    my $B = Test::More->builder;

    %CB = ( vis => $vis, invis => $invis, args => $args );

    my $rv = eval {
        fakerequire $name =>  "package $Pkg;" . q{
            {
                use DBIx::Irian @{$::CB{args}};
                BEGIN { $::CB{vis}->() }
                $::CB{invis}->("at runtime");
            }
            BEGIN { $::CB{invis}->("after scope end") }
            1;
        };
        1;
    };

    $B->ok($rv, $name) or $B->diag("\$\@: $@");
}

my %Utils = (
    Irian   => [qw/ 
        trace tracex register_utils
        install_sub find_sym qualify load_class
        register lookup    
    /],
    Query   => [qw/ djoin expand_query                          /],
    Inflate => [qw/ register_inflators                          /],
);
my %Sugar = (
    QuerySet    => [qw/
        row_class setup_row_class
        method queryset query cursor detail action
    /],
    DB          => [],
    Row         => [qw/ columns extends inflate /],
);
push @{$Sugar{DB}}, @{$Sugar{QuerySet}};
push @{$Sugar{Row}}, @{$Sugar{QuerySet}};

my %Pkg = (
    Irian   => "DBIx::Irian",
    Query   => "DBIx::Irian::Query",
    Inflate => "DBIx::Irian::Inflate",

    QuerySet    => "DBIx::Irian::QuerySet",
    DB          => "DBIx::Irian::DB",
    Row         => "DBIx::Irian::Row",
);
my @Vars = qw(
    %P %Q
    @Arg %Arg @ArgX %ArgX @ArgQ %ArgQ
    $Cols %Cols %Queries
    %Self %SelfX %SelfQ
);

my @not = ("", "not ");

sub check_vars {
    my ($if, $pkg, $name) = @_;
    my $B = Test::More->builder;
    for (@Vars) {
        my ($sg, $nm) = /(.)(.*)/;
        my $code = qq{ 
            \\${sg}${pkg}::$nm == \\${sg}DBIx::Irian::Query::$nm
        };
        if ($if xor eval $code) {
            $B->ok(0, "$_ is $not[$if]exported $name");
            return;
        }
    }
    $B->ok(1, "Query's vars are $not[!$if]exported $name");
}

irian_ok [], sub {
    cant_ok @{$Utils{$_}}, "$_ utils are not exported by default"
        for keys %Utils;

    cant_ok @{$Sugar{$_}}, "$_ sugar is not exported by default"
        for keys %Sugar;

    check_vars 0, $Pkg, "by default";
}, sub { }, "empty import list OK";

irian_ok [undef], sub {
    cant_ok @{$Utils{$_}}, "$_ utils are not exported with undef"
        for keys %Utils;

    cant_ok @{$Sugar{$_}}, "$_ sugar is not exported with undef"
        for keys %Sugar;

    check_vars 0, $Pkg, "with undef";
}, sub { }, "undef import OK";

for (
    map { 
        my $m = $_; 
        map [$Pkg{$m}, $_], @{$Utils{$m}} 
    } keys %Utils
) {
    my ($m, $u) = @$_;
    irian_ok [undef, $u],
        sub { is_import $u, $m,     "$u can be imported explicitly" },
        sub { cant_ok $u,           "$u is invisible $_[0]"         },
        "import just $u";
}

for my $c (keys %Sugar) {
    irian_ok [$c],
        sub {
            for my $s (@{$Sugar{$c}}) {
                ok $Pkg->can($s),   "$c imports $s";
            }
        },
        sub {
            my ($when) = @_;
            for my $s (@{$Sugar{$c}}) {
                cant_ok $s,         "$c removes $s $when";
            }
        },
        "import $c";

    ok $Pkg->isa($Pkg{$c}), "import $c sets up inheritance";
}

done_testing;
