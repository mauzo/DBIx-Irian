use Module::Build;

Module::Build->new(
    module_name         => "DBIx::Irian",
    license             => "bsd",
    configure_requires  => {
        "Module::Build"     => "0.38",
    },
    build_requires      => {
        "Test::More"        => "0.96",
        "Test::Exports"     => "1",
        "DBD::Mock"         => "0",
    },
    requires            => {
        "parent"                => "0",
        "DBIx::Connector"       => "0",
        "Tie::OneOff"           => "0",
        "B::Hooks::EndOfScope"  => "0",
        "B::Hooks::AtRuntime"   => "0",
        "Scope::Upper"          => "0",
        "Sub::Name"             => "0",
    },
    meta_merge          => {
        resources => {
            repository => "http://github.com/mauzo/DBIx-Irian",
            bugtracker =>
            "https://rt.cpan.org/Public/Dist/Display.html?Name=DBIx-Irian",
        },
    },
)->create_build_script;
