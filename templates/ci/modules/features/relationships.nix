{ denTest, ... }:
{
  flake.tests.relationships = {

    # A declared relationship fires: its target stage behavior appears in the
    # resolved NixOS config of the host.
    test-relationship-fires = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.stages.test-rel-target = {
          includes = [ ];
          nixos.users.users.tux.description = "from-rel-target-stage";
        };

        den.relationships.host-to-test-rel = {
          from = "host";
          to = "test-rel-target";
          resolve = _: [ { } ];
        };

        expr = igloo.users.users.tux.description;
        expected = "from-rel-target-stage";
      }
    );

    # Relationships coexist with existing ctx transitions: both the
    # relationship target stage and a ctx.into transition contribute to
    # the resolved NixOS config without clobbering each other.
    test-relationship-coexists-with-ctx-into = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.stages.test-rel-coexist = {
          includes = [ ];
          nixos.networking.hostName = "from-rel-stage";
        };

        den.stages.default = {
          includes = [ ];
          nixos.users.users.tux.description = "from-default-stage";
        };

        den.relationships.host-to-test-rel-coexist = {
          from = "host";
          to = "test-rel-coexist";
          resolve = _: [ { } ];
        };

        expr = [
          igloo.networking.hostName
          igloo.users.users.tux.description
        ];
        expected = [
          "from-rel-stage"
          "from-default-stage"
        ];
      }
    );

  };
}
