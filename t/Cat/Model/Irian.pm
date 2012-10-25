package t::Cat::Model::Irian;

use Moose;
extends "Catalyst::Model::Irian";

__PACKAGE__->config(
    DB  => "t::DB::DB",
    dsn => "dbi:Mock:",
);

1;
