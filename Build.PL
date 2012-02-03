use Module::Build;

Module::Build->new(
    module_name         => "DBIx::OQM",
    license             => "bsd",
    configure_requires  => {
        "Module::Build"     => "0.38",
    },
    build_requires      => {
        "Test::More"        => "0.65",
    },
    requires            => {
        "DBIx::Connector"   => "0",
        "String::Defer"     => "0",
        "Tie::OneOff"       => "0",
    },
    meta_merge          => {
        resources => {
            repository => "http://github.com/mauzo/DBIx-OQM",
            bugtracker =>
            "https://rt.cpan.org/Public/Dist/Display.html?Name=DBIx-OQM",
        },
    },
)->create_build_script;
