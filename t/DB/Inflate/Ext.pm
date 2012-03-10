package t::DB::Inflate::Ext;

use DBIx::Irian "Row";
extends "Inf";
columns qw/myplain myfoo/;
inflate myfoo => "foo";

1;
