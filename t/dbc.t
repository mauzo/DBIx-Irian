use t::Util;

use Carp;
$SIG{__DIE__} = \&Carp::croak;

require_ok "t::DB::DB";

my @rec;

{   package t::DBC;

    no warnings "once";    
    use parent "DBIx::Connector";
    
    for my $m (qw/run svp txn/) {
        no strict "refs";
        *$m = sub {
            my $cb = pop;
            push @rec, [$m, @_];
            $cb->();
        };
    }
}

{   no warnings "redefine";
    my $oldnew = DBIx::Connector->can("new");
    *DBIx::Connector::new = sub {
        push @rec, [new => @_];
        goto &$oldnew;
    };
}

my @dsn         = (dsn => "dbi:Mock:");
my @newargs     = (new => "DBIx::Connector", "dbi:Mock:");
my $dbiargs     = { RaiseError => 1, AutoCommit => 1 };
my @dbcmodes    = qw/ping fixup no_ping/;
my $defmode     = "no_ping";

{
    @rec = ();
    my $D = t::DB::DB->new(@dsn,
        user        => "bob",
        password    => "bill",
        dbi         => { RaiseError => 0, AutoCommit => 0 },
    );

    is_deeply \@rec, [
        [ @newargs, "bob", "bill", { RaiseError => 0, AutoCommit => 0 } ],
    ],                          "DB calls DBC->new with explicit args";

    can_ok $D, "dbc";

    my $dbc = $D->dbc;
    isa_ok $dbc, "DBIx::Connector", "DB->dbc";

    can_ok $D, "dbh";
    is $D->dbh, $dbc->dbh,      "DB->dbh delegates to DBC";
    is $dbc->mode, $defmode,    "DBC defaults to $defmode mode";
}

{
    @rec = ();
    my $D = t::DB::DB->new(@dsn);

    is_deeply \@rec, [
        [ @newargs, undef, undef, $dbiargs ],
    ],                          "DB calls DBC->new with default args";
}

for (@dbcmodes) {
    @rec = ();
    my $D = t::DB::DB->new(@dsn,
        mode    => $_,
    );

    is_deeply \@rec, [
        [ @newargs, undef, undef, $dbiargs ], 
    ],                          "DB->new with mode=>$_";

    is $D->dbc->mode, $_,       "DB->new(mode=>$_) sets DBC->mode";
}

{
    my $DBC = t::DBC->new("dbi:Mock:", undef, undef);
    # clear @rec *after* the ->new above
    @rec = ();

    my $D = t::DB::DB->new(
        dbc     => $DBC,
    );

    is_deeply \@rec, [],        "DB->new with explicit dbc";
    is $D->dbc, $DBC,           "DB retains passed-in DBC";

    my $cb = sub { push @rec, "cb" };

    my $ck = sub {
        my ($m, $dbc, $mode, $name);
    };

    for my $im (qw/txn svp/) {
    for my $id (undef, @dbcmodes) {
    for my $om (undef, qw/txn svp/) {
    for my $od (undef, ($om ? @dbcmodes : ())) {

        my $doit = sub {
            @rec = ();
            $D->$im($id // (), $cb);
        };
        if (defined $om)    { $D->$om($od // (), $doit) }
        else                { $doit->()                 }

        my $em = $om ? $im : "txn";
        my $ed = $id // $defmode;
        my $name = sprintf "DB->%s with %s mode %s",
            $im, $id // "no", 
            $om ? "in $om" . ($od ? " with $od" : "")
                : "at top-level";

        is_deeply   $rec[0], [$em, $DBC, $ed],  "$name calls $em";
        is          $rec[1], "cb",              "$name calls callback";
    } } } }
}

for my $old (@dbcmodes) {
    my $DBC = t::DBC->new("dbi:Mock:", undef, undef);
    $DBC->mode($old);

    {
        my $D = t::DB::DB->new(dbc => $DBC);
        is $DBC->mode($old), $old,  "DB->new with no mode leaves $old";
    }

    for my $new (@dbcmodes) {
        $DBC->mode($old);
        my $D = t::DB::DB->new(dbc => $DBC, mode => $new);
        is $DBC->mode($new), $new,  "DB->new(mode=>$new) overrides $old";
    }
}

done_testing;
