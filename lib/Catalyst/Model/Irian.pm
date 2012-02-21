package Catalyst::Model::Irian;

use 5.010;
use Moose;
use Catalyst::Utils;
use PerlIO::via::Logger;

our $VERSION = "1";

extends "Catalyst::Model";

sub COMPONENT {
    my ($self, $app, $args) = @_;

    my $conf = $self->merge_config_hashes($self->config, $args);
    # no need to pass Cat cruft in to Irian
    delete $conf->{catalyst_component_name};

    my $dbclass = delete $conf->{DB};
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
