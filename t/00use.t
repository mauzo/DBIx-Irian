#!/usr/bin/perl

use strict;
use warnings;

use Test::More;

use_ok "DBIx::Irian";
use_ok "DBIx::Irian::QuerySet";
use_ok "DBIx::Irian::Inflate";
use_ok "DBIx::Irian::Row::Generic";
use_ok "DBIx::Irian::Driver::Pg";
use_ok "DBIx::Irian::Query";
use_ok "DBIx::Irian::Cursor";
use_ok "DBIx::Irian::Row";
use_ok "DBIx::Irian::Driver";
use_ok "DBIx::Irian::DB";
use_ok "PerlIO::via::Logger";
SKIP: {
    eval "require Catalyst::Utils; 1" or skip "No Catalyst", 1;
    use_ok "Catalyst::Model::Irian";
}

Test::More->builder->is_passing
    or BAIL_OUT "Modules will not load!";

done_testing;
