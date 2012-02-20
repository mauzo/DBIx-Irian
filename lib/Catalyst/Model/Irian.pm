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
    my $trace   = delete $conf->{redirect_dbi_trace};

    Catalyst::Utils::ensure_class_loaded $dbclass;
    my $db = $dbclass->new($conf);
    
    if ($trace) {
        # Make DBI's tracing log through Catalyst. Unfortunately this is
        # a global setting, for anything in the program using DBI.

        my $level = $trace eq "1" ? "debug" : $trace;
        open my $TR, ">:via(Logger)", {
            logger  => $app->log,
            level   => $level,
            prefix  => "DBI",
        };
        DBI->trace(DBI->trace, $TR);
    }

    return $db;
}

1;
