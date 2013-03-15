package DBIx::Irian;

=head1 NAME

DBIx::Irian - Not an ORM, but an object-to-query mapper

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

What follows is reference documentation for the DBIx::Irian module
itself. For a general high-level introduction to Irian please see
L<DBIx::Irian::Tutorial|DBIx::Irian::Tutorial>.

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
        my ($pkg, $sym, $thing) = @_;
        no warnings "once";

        if ($sym eq "::") {
            no strict "refs";
            return \%{"$pkg\::"};
        }
        
        unless (defined $thing) {
            my ($sig, $name) = $sym =~ /(.)(.*)/;
            ($sym, $thing) = ($name, $sigs{$sig});
        }

        my $gv = do {
            no strict "refs";
            \*{"$pkg\::$sym"};
        };
        return *$gv{$thing};
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
            $Utils{$_} = find_sym $pkg, $_, "CODE";
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
    install_sub find_sym qualify load_class load_module
    register lookup
);

=head2 Importing Irian

    use DBIx::Irian $parent, @utils;

Importing DBIx::Irian does several things:

=over 4

=item 1

Imports C<strict>, C<warnings> and C<feature ":5.10">.

=item 2

Sets up the current package as a subclass of C<"DBIx::Irian::$parent">.

=item 3

Imports a number of 'sugar' subs into your namespace. The subs imported
are those supplied by the parent class you requested, and those supplied
by B<its> parents. See L</Sugar> below for a list.

=item 4

Imports a number of utility subs, as listed in C<@utils>.

=item 5

Imports the L<magic variables from
DBIx::Irian::Query|DBIx::Irian::Query/MAGIC VARIABLES>.

=item 6

Sets things up so that, when perl finished compiling the current scope,
any subs imported by 3 or 4 above will be removed. This will prevent
them from being visible as methods. Also, any subs listed in the
C<@CLEAN> package variable in the current package will be similarly
removed.

=back

=head2 Sugar

This is a list of which sugar subs are supplied by which
DBIx::Irian::C<*> parent classes.

=over 4

=item C<method>

=item C<query>

=item C<cursor>

=item C<detail>

=item C<action>

=item C<queryset>

=item C<setup_row_class>

=item C<row_class>

L<QuerySet|DBIx::Irian::QuerySet>, Row, DB

=item C<columns>

=item C<extends>

=item C<inflate>

L<Row|DBIx::Irian::Row>

=back

=head2 Utility functions

The following utility functions can be exported from Irian, but are
documented in other modules:

=over 4

=item C<djoin>

=item C<expand_query>

L<DBIx::Irian::Query|DBIx::Irian::Query>

=item C<register_inflators>

L<DBIx::Irian::Inflate|DBIx::Irian::Inflate>

=back

The remaining utility functions are defined by DBIx::Irian itself.

=head3 trace

=head3 tracex

    trace $level, $msg;
    tracex { ...; @msg } $level;

Emit trace information to the current trace log, which by default means
calling C<warn>. Tracing is only done (and, in the case of C<tracex>,
the whole block only executed) if C<$level> is a currently-active trace
level, and C<"$level: "> is prepended to the message. Currently-defined
trace levels are

=over 4

=item COL

Column definitions in Row classes.

=item CUR

Cursor operations.

=item DRV

Driver operations.

=item EXP

Query expansion.

=item GEN

Operations performed by C<setup_row_class>.

=item ISA

C<@ISA> manipulation.

=item QRY

Query definitions.

=item REG

Registration and lookup of Irian subclasses.

=item ROW

Row class setup.

=item SQL

Query execution.

=item SYM

Symbol table manipulation.

=back

Core Irian trace levels will always be all-caps, so if you want to
define your own make them lower- or mixed-case.

C<tracex> sets C<$" = "]["> and swallows all warnings while executing
the block, and then calls C<trace> with each message returned.

=head3 set_trace_flags

    DBIx::Irian::set_trace_flags %f;

(This function is never exported; call it by its full name.)

Sets or clears the currently-active trace flags. C<%f> should be a list
of (level, boolean) pairs; any levels present in the list will be
switched on or off, any not mentioned will be left alone.

=head3 set_trace_to

    DBIx::Irian::set_trace_to sub {...};

(This function is never exported: call it by its full name.) 

Redirect the tracing output. The supplied sub will be called for each
traced message with the message as its only argument.

    DBIx::Irian::set_trace_to undef;

Redirect tracing back to the default destination, which is to send it
through C<warn>.

=cut

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

=head3 load_class

    load_class $for, $class, $type;

First this finds the 'current DB' for the package C<$for>. This is
defined like this:

=over 4

=item *

A class which inherits from DBIx::Irian::DB (with C<use DBIx::Irian
"DB">) is its own current DB.

=item *

A class which is loaded by C<load_class> acquires the current DB of the
class it was loaded C<$for>.

=item *

Any other class has no current DB, and will throw an error.

=back

This means you must not attempt to set up inheritance from Irian classes
manually, or to load subsidiary classes by hand.

Once the appropriate DB class has been determined, C<$class> is
qualified with respect to that class. If C<$class> begins with C<"+">,
that is stripped off; otherwise the DB class name is prepended. The
class is loaded, and C<load_class> checks it called C<use DBIx::Irian
$type;>.

Returns the fully-qualified name of the loaded class.

=cut

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
    # as of 5.16 'use 5.x' no longer loads feature.pm
    require feature;
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

=head1 ENVIRONMENT

If the variable C<IRIAN_TRACE> is set in the environment when Irian is
loaded, its value will be split on comma and the corresponding trace
levels switched on.

=head1 WHY 'IRIAN'?

There is a move in Perl culture at the moment towards giving modules
names that are names, rather than names that attempt to be descriptions.
So, Irian is named after Orm Irian from Ursula Le Guin's 'Earthsea'
books. 

=head1 SEE ALSO

Irian uses L<DBI|DBI> underneath, obviously; also
L<DBIx::Connector|DBIx::Connector> to keep the connection to the
database alive.

L<DBIx::Class|DBIx::Class> and L<Fey::ORM|Fey::ORM> are good examples of
more conventional ORMs.

For using Irian with L<Catalyst|Catalyst>, see
L<Catalyst::Model::Irian|Catalyst::Model::Irian>.

=head1 BUGS

Please report any bugs to <bug-DBIx-Irian@rt.cpan.org>.

Quite a lot of the interface is rather rough, and will have to change
incompatibly. For a start, I am internally doing a lot of metaclassish
stuff, so I really ought to port this all to L<Moose|Moose>; I don't yet
know what changes that will require.

The distinction between 'sugar' and 'utility subs' is not terribly clear
to an outside user. (The difference arises from the way they are defined
and used internally, but you don't care about that.) This should be
fixed, probably by (lexically) exporting all the utilities all the time.

The magic variables are currently exported unconditionally and
permanently. This is perhaps not the best idea, but I haven't yet tested
if the replace-the-glob trick works for variables as well as for subs.

=head1 AUTHOR

Ben Morrow <ben@morrow.me.uk>

=head1 COPYRIGHT

Copyright 2012 Ben Morrow.

Released under the 2-clause BSD licence.
