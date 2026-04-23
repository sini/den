{ denTest, ... }:
{
  flake.tests.ctx-compat = {

    test-ctx-shim-forwards-to-stages = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.ctx.host = {
          nixos.networking.hostName = "from-ctx-shim";
        };

        expr = igloo.networking.hostName;
        expected = "from-ctx-shim";
      }
    );

    test-ctx-shim-includes = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.ctx.host.includes = [
          { nixos.users.users.tux.description = "from-ctx-include"; }
        ];

        expr = igloo.users.users.tux.description;
        expected = "from-ctx-include";
      }
    );

    # den.ctx.host.into forwards to den.stages.host.meta.into,
    # firing the transition through the pipeline.
    test-ctx-shim-into = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.stages.test-into-target = {
          includes = [ ];
          nixos.users.users.tux.description = "from-into-target";
        };

        den.ctx.host.into = _ctx: {
          test-into-target = [ { } ];
        };

        expr = igloo.users.users.tux.description;
        expected = "from-into-target";
      }
    );

  };
}
