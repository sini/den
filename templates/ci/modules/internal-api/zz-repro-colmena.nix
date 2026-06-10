{ denTest, ... }:
{
  flake.tests.zz-repro-colmena = {
    test-schema-include-instantiate = denTest (
      { den, config, ... }:
      {
        den.policies.cap = { host, ... }: [
          (den.lib.policy.instantiate {
            name = "${host.name}-mod";
            inherit (host) class;
            instantiate = { modules, ... }: modules;
            intoAttr = [ "capModules" host.name ];
          })
        ];
        den.schema.host.includes = [ den.policies.cap ];
        den.hosts.x86_64-linux.igloo.users.tux = { };

        expr = (config.flake.capModules or { }) ? igloo;
        expected = true;
      }
    );
  };
}
