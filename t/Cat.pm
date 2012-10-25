package t::Cat;

use Moose;
use Catalyst;
use t::Log;

extends "Catalyst";

sub build_app_ok {
    my ($app, $config, $n) = @_;

    $config and $app->config($config);
    $app->log(t::Log->new);
    $app->setup;
    my $c = $app->new;
    Test::More::isa_ok $c, __PACKAGE__, "can build app with $n";
    $c;
}

1;
