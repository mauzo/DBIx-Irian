use t::Util;

my $DB      = "t::DB::Cursor";
my $Row     = "$DB\::Row";
my $Curs    = "DBIx::Irian::Cursor";

(my $pm = $DB) =~ s!::!/!g;
require "$pm.pm";

my $fld = [qw/one two three/];
my @rows = (
    [qw/un deux trois/], 
    [qw/eins zwei drei/],
    [qw/unos dos tres/],
);

sub cursor_connect_db {
    my $D = $DB->new("dbi:Mock:");
    my $dbh = $D->dbh;

    for (
        [[],            ],
        [$fld, @rows,   ],
        [[],            ],
    ) {
        $dbh->{mock_add_resultset} = $_;
    }

    ($D, $dbh);
}

my %Defaults = (
    batch   => 20,
);

sub check_cursor_prop {
    my ($mk, $prop, $name) = @_;

    my ($D, $dbh)   = cursor_connect_db;
    my $c           = $mk->($D);

    isa_ok $c, $Curs,               $name;

    is $c->DB, $D,                  "$name has correct DB";

    for (keys %$prop) {
        is_deeply $c->$_, $$prop{$_}, "$name has correct $_";
    }
    for (keys %Defaults) {
        exists $$prop{$_} and next;
        is $c->$_, $Defaults{$_},   "$name has correct default $_";
    }

    undef $c;
    my $sql = $$prop{sql};
    check_history $dbh, [
        "DECLARE $sql",     $$prop{bind},
        "CLOSE $sql",       [],
    ], "$name (unread)";
}

sub check_cursor_next {
    my ($mk, $row, $sql, $bind, $name) = @_;

    my ($D, $dbh)   = cursor_connect_db;
    my $c           = $mk->($D);
    my @rs          = @rows;

    check_row $c->peek, $row, $fld, $rs[0], "$name ->peek";

    for my $which (qw/first second/) {
        my $r = $c->next;
        my $want = shift @rs;
        check_row $r, $row, $fld, $want, "$name $which ->next";
    }

    check_row <$c>, $row, $fld, shift(@rs), "<$name>";

    ok !defined $c->next,       "$name ->next returns undef when empty";

    undef $c;

    check_history $dbh, [
        "DECLARE $sql",         $bind,
        "FETCH 20 FROM $sql",   [],
        "FETCH 20 FROM $sql",   [],
        "CLOSE $sql",           [],
    ], "$name (next)";
}

sub check_cursor_all {
    my ($mk, $row, $sql, $bind, $name) = @_;

    my %all = (
        "$name ->all"   => sub { $_[0]->all },
        #"\@{$name}"     => sub { @{ $_[0] } },
    );
    for my $nm (keys %all) {
        my ($D, $dbh)   = cursor_connect_db;
        my $c           = $mk->($D);
        my @rs          = @rows;
        my @got         = $all{$nm}->($c);

        is @got, @rs,       "$nm returns the right number of rows";
        check_row $got[$_], $row, $fld, $rs[$_], "$nm #$_"
            for 0..$#rs;

        undef $c;
        check_history $dbh, [
            "DECLARE $sql",         $bind,
            "FETCH 20 FROM $sql",   [],
            "FETCH 20 FROM $sql",   [],
            "CLOSE $sql",           [],
        ], $nm;
    }
}

sub check_cursor {
    my ($mk, $prop, $name) = @_;

    my @want = @{$prop}{qw/row sql bind/};

    check_cursor_prop $mk, $prop, $name;
    check_cursor_next $mk, @want, $name;
    check_cursor_all $mk, @want, $name;
}

my %prop = (
    sql     => "SELECT sql_only",
    bind    => [],
    row     => $Row,
);
check_cursor sub { $Curs->new(%prop, DB => $_[0]) }, 
    \%prop, 
    "Cursor->new";

check_cursor sub { $_[0]->curs }, {
    sql     => "SELECT sugar",
    bind    => [],
    row     => $Row,
}, "cursor sugar";

check_cursor sub { $_[0]->args("foo") }, {
    sql     => "SELECT ? FROM args",
    bind    => ["foo"],
    row     => $Row,
}, "cursor sugar with \@Arg";

done_testing;
