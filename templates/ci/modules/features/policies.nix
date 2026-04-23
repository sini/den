{ denTest, ... }:
{
  flake.tests.policies = {

    test-policy-fires = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.stages.test-rel-target = {
          includes = [ ];
          nixos.users.users.tux.description = "from-rel-target-stage";
        };

        den.policies.host-to-test-rel = {
          from = "host";
          to = "test-rel-target";
          resolve = _: [ { } ];
        };

        expr = igloo.users.users.tux.description;
        expected = "from-rel-target-stage";
      }
    );

    # Both a policy target stage and an into transition contribute
    # to the resolved NixOS config without clobbering each other.
    test-policy-coexists-with-into = denTest (
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

        den.policies.host-to-test-rel-coexist = {
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
