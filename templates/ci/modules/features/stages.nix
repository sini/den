{ denTest, ... }:
{
  flake.tests.stages = {

    # Behavior set on den.stages.default appears in the resolved NixOS config.
    test-stage-default-nixos = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.stages.default = {
          includes = [ ];
          nixos.users.users.tux.description = "from-default-stage";
        };

        expr = igloo.users.users.tux.description;
        expected = "from-default-stage";
      }
    );

    # den.stages.default and den.default coexist:
    # both contribute to the resolved NixOS config without clobbering each other.
    test-stage-default-coexists-with-ctx = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.default.nixos.networking.hostName = "from-ctx-default";
        den.stages.default = {
          includes = [ ];
          nixos.users.users.tux.description = "from-default-stage";
        };

        expr = [
          igloo.networking.hostName
          igloo.users.users.tux.description
        ];
        expected = [
          "from-ctx-default"
          "from-default-stage"
        ];
      }
    );

    # Behavior set on den.stages.user appears in the resolved NixOS config
    # for each user (user stage is reached from host via policies).
    test-stage-user-nixos = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.stages.user = {
          includes = [ ];
          nixos.users.users.tux.description = "from-user-stage";
        };

        expr = igloo.users.users.tux.description;
        expected = "from-user-stage";
      }
    );

  };
}
