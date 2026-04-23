{ denTest, ... }:
{
  flake.tests.ctx-compat = {

    # den.ctx.host forwards to den.stages.host with deprecation warning.
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

    # den.ctx.host.includes forwards correctly.
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

  };
}
