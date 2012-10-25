package Catalyst::Model::Irian;

=head1 NAME

Catalyst::Model::Irian - Use an Irian DB as a Catalyst Model

=cut

use 5.010;
use Moose;
use Catalyst::Utils;
use PerlIO::via::Logger;

our $VERSION = "1";

extends "Catalyst::Model";

=head1 SYNOPSIS

    package MyApp::Model::DB;

    use Moose;
    extends "Catalyst::Model::Irian";

    __PACKAGE__->config(
        DB      => "MyApp::DB",
        dsn     => "dbi:...",
    );

=head1 DESCRIPTION

This is a L<Catalyst|Catalyst> L<Model|Catalyst::Model> for connecting
to an L<Irian|DBIx::Irian> database. It overrides the C<COMPONENT>
method, so C<< $c->model >> will return an L<Irian::DB|DBIx::Irian::DB>
object rather than one derived from Catalyst::Model.

=head2 Configuration

The following keys can be passed to C<< __PACKAGE__->config >> or
specified in your app's config file.

=over 4

=item C<DB>

The name of the DBIx::Irian::DB class to instantiate. Required.

=item C<redirect_trace>

If this is set to C<1>, both Irian and DBI will have their logging
redirected through the Catalyst logger. By default logging will be at
the C<debug> level; if this is set to a string, that method will be
called on the log object instead.

This redirection is done when the model is instantiated, and has global
effect. All Irian and all DBI logging in the program will be affected.

=item C<dsn>

=item C<user>

=item C<password>

=item C<mode>

=item C<dbi>

=item C<dbc>

=item C<driver>

These will be passed through to L<C<< DB->new >>|DBIx::Irian::DB/new>.
At least C<dsn> is required. Be aware that C<dbc> and C<driver> need an
object, so they cannot be specified in a config file.

=back

=cut

sub COMPONENT {
    my ($self, $app, $args) = @_;

    my $conf = $self->merge_config_hashes($self->config, $args);
    # no need to pass Cat cruft in to Irian
    delete $conf->{catalyst_component_name};

    my $dbclass = delete $conf->{DB}
        or Catalyst::Exception->throw("No DB class supplied for $self");
    my $trace   = delete $conf->{redirect_trace};

    Catalyst::Utils::ensure_class_loaded $dbclass;
    my $db = $dbclass->new($conf);
    
    if ($trace) {
        my $level   = $trace eq "1" ? "debug" : $trace;
        my $log     = $app->log;

        # Make DBI's tracing log through Catalyst. Unfortunately this is
        # a global setting, for anything in the program using DBI.
        open my $TR, ">:via(Logger)", {
            logger  => $log,
            level   => $level,
            prefix  => "DBI",
        };
        DBI->trace(DBI->trace, $TR);

        # Make Irian's tracing log through Catalyst, too
        DBIx::Irian::set_trace_to(sub { $log->$level($_[0]) });
    }

    return $db;
}

1;

=head1 SEE ALSO

See L<DBIx::Irian> for bug reporting and other general information.

L<Catalyst>, L<Catalyst::Model>, L<Catalyst::Model::Adaptor>.

L<DBI> log redirection is implemented using L<PerlIO::via::Logger>.

=head1 COPYRIGHT

Copyright 2012 Ben Morrow.

Released under the 2-clause BSD licence.

