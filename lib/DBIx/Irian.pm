package DBIx::Irian;

=head1 NAME

DBIx::Irian - Not an ORM, but an object <-> query mapper

=cut

use 5.010;
use warnings;
use strict;
use mro;

our $VERSION = "0";

use Carp;
use Sub::Name               qw/subname/;
use B::Hooks::EndOfScope;
use B::Hooks::AtRuntime;
use Scope::Upper            qw/reap CALLER/;

=head1 SYNOPSIS

    package My::DB;
    use DBIx::Irian "DB";

    query book => Book =>
        "SELECT $Cols FROM $Q{book} WHERE $Q{isbn} = $Arg[0]";
    cursor books => Book =>
        "SELECT $Cols FROM $Q{book} ORDER BY $Q{title}";

    ##
    package My::DB::Book;
    use DBIx::Irian "Row";

    columns qw/id isbn title/;
    inflate isbn => "ISBN";

    detail authors =>
        "SELECT $Q{name} FROM $Q{author} WHERE $Q{book} = $Self{id}";

    ##
    package main;
    use My::DB;

    my $DB = My::DB->new("dbi:Pg:");
    my $book = $DB->book("0596000278");
    say $book->title, " was written by ", join ", ", $book->authors;

=head1 DESCRIPTION

Irian is a system for mapping method calls to SQL queries, and returning
the results as objects, but it isn't a conventional ORM. Ordinarily an
ORM wants to know the structure of your database (which tables have which
fields, how they are related, and so on), and it uses that information
to write your queries for you. While this is often very useful,
particularly if you don't like writing SQL or if you want your
application to be portable between databases, it can be limiting when
you know which database you are writing against and you want to make use
its more advanced features.

First a disclaimer: the current version should be considered alpha, at
best. While I don't believe there are any serious bugs, at least in
normal usage, some of the interfaces are probably not entirely stable
yet. If you're interested in making serious use of this it might be a
good idea to let me know, so I can keep track of which bits people are
depending on and let you know if anything is going to change.

=head2 Databases

A system built using Irian has a single entry point, an object
inheriting from L<DBIx::Irian::DB|DBIx::Irian::DB>. This object holds
the connection to the database, and has methods for making queries.

A simple, self-contained database class might look like this:

    package My::DB;
    use DBIx::Irian "DB";

    setup_row_class Book => qw/id isbn title/;
    query book => Book => <<SQL;
        SELECT $Cols FROM $Q{book} WHERE $Q{isbn} = $Arg[0]
    SQL

    1;

and might be used like this

    my $DB = My::DB->new("dbi:Pg:");
    my $book = $DB->book("0596000278");

Even with such a relatively simple example, there's quite a lot
happening, so let's go through it.

=head2 Importing from C<Irian>

The first thing to notice is that C<warnings> and C<strict> are missing.
This is not accidental: C<use DBIx::Irian> does the equivalent of

    use strict;
    use warnings;
    use feature ":5.10";

for you. The next is the C<"DB"> argument to C<use>: this does two
things.

First, it sets up the current package to inherit from
L<DBIx::Irian::DB|DBIx::Irian::DB>. Second, it exports a number of
'syntactic sugar' subs into the current namespace, but arranges for them
to disappear again when the current scope has finished compiling. This
means you can have a method called (say) C<query> despite there being a
sugar by that name. These 'sugars' are the main interface for setting up
Irian subclasses.

=head2 Queries

Ignore the call to C<setup_row_class> for a moment, and look at the
call to C<query>:

    query book => Book => <<SQL;
        SELECT $Cols FROM $Q{book} WHERE $Q{isbn} = $Arg[0]
    SQL

This sets up a method to run a query, which will end up something like

    SELECT "id", "isbn", "title" FROM "book" WHERE "isbn" = ?

with the first argument to the method passed in as the value for the
placeholder. The second argument to C<query>, C<"Book">, asks for the
rows returned by the query to be packed up into C<My::DB::Book> objects.

=head2 Rows

This row class, C<My::DB::Book>, is a class you need to create yourself,
though Irian will load it for you when it is needed. It needs to inherit
from L<DBIx::Irian::Row|DBIx::Irian::Row>, and a simple case might look
like

    package My::DB::Book;
    use DBIx::Irian "Row";

    columns qw/id isbn title/;
    1;

This says that a query using the C<Book> row class is expected to
return rows with three columns, and those columns will be accessible
with the C<< ->id >>, C<< ->isbn >> and C<< ->title >> methods on the
row object.

Note that these are columns returned by the I<query>, not the columns on
the constituent tables which an ORM like C<DBIx::Class> would give you.
If a query joins across three tables and returns one field from each,
the row class still has three fields accessible directly from that
object. Note also that it's perfectly sensible to have several queries
use the same C<Row> if they return compatible data: for instance, you
might have C<< ->all_books >> and C<< ->book_by_title >> return C<Book>s
as well.

When a C<Row> class has nothing but a C<columns> declaration, you can
avoid creating a whole module file just for that by using
C<setup_row_class>. The call in C<My::DB>,

    setup_row_class Book => qw/id isbn title/;

is equivalent to the C<My::DB::Book> example above. If you want to do
more than that, you'll need a proper module file.

You can set up C<query> methods on a C<Row> class: this is how you make
queries for related records. So, for instance, we could have

    query authors => Author => <<SQL;
        SELECT $Cols FROM $Q{author} WHERE $Q{book} = $Self{id}
    SQL
    
which might look up authors based on the C<Book>'s C<< ->id >>.

=head2 Magic variables

By now you must be wondering about these variables that keep getting
interpolated into the SQL. The full documentation for them is in
L<DBIx::Irian::Query|DBIx::Irian::Query>, but the short version is that
they don't expand immediately, the expansion is deferred until the
method is called and the query is run. The most important are:

=over 4

=item %Q

This expands to an SQL identifier, properly quoted for the database you
are using.

=item $Cols

This expands to the column names of the C<Row> this query is using,
identifier-quoted and comma-separated. In simple cases this allows you
to fill in the C<SELECT> list without repeating yourself.

=item %Cols

An expression like C<$Cols{tab}> expands to the same column names (for
any given query) as C<$Cols>, but with the field names qualified with a
table name. So whereas C<$Cols> might expand to

    "one", "two", "three"

C<$Cols{table}> might expand to

    "table"."one", "table"."two", "table"."three"

This is useful when you need to join in other tables to select the rows
you want, and there might be column name conflicts.

=item %P

This expands to a C<"?"> placeholder, and arranges for the key used to
be passed to DBI as the corresponding bind value.

=item @Arg

This expands to a placeholder which will be bound to one of the
arguments passed to the method call. Arguments are numbered from 0,
discounting the implicit object argument.

=item %Self

This takes as a key the name of a method, and calls that method (with no
arguments) on the current object. The result is bound to a placeholder,
as with C<@Arg>.

=back

There are more, but they are more obscure; see the
L<Query|DBIx::Irian::Query> documentation for details.

=cut

# The bootstrapping order is rather specific. Currently that means the
# exports for this module are buried halfway down the file, in a call to
# register_utils. Probably Trace, Sym, and Util should go into their own
# modules.

{
    my ($TraceLog, %TraceFlags);

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

    sub set_trace_to { 
        $TraceLog = $_[0] // sub { warn "$_[0]\n" };
    }
    set_trace_to undef;

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

=head1 BUGS

Please report any bugs to <bug-DBIx-Irian@rt.cpan.org>.

=head1 AUTHOR

Ben Morrow <ben@morrow.me.uk>

=head1 COPYRIGHT

Copyright 2012 Ben Morrow <ben@morrow.me.uk>

Released under the 2-clause BSD licence.
