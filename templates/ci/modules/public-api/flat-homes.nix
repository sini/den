{ denTest, ... }:
{
  flake.tests.flat-homes = {
    test-flat-home-two-level-shape = denTest (
      { den, ... }:
      {
        den.homes."tux@igloo" = {
          system = "x86_64-linux";
        };

        expr = builtins.attrNames den.homes;
        expected = [ "x86_64-linux" ];
      }
    );

    test-flat-home-name-parsing = denTest (
      { den, ... }:
      {
        den.homes."tux@igloo" = {
          system = "x86_64-linux";
        };

        expr = {
          inherit (den.homes.x86_64-linux."tux@igloo")
            name
            userName
            hostName
            system
            ;
        };
        expected = {
          name = "tux";
          userName = "tux";
          hostName = "igloo";
          system = "x86_64-linux";
        };
      }
    );

    test-flat-home-coexists-with-legacy = denTest (
      { den, ... }:
      {
        den.homes.x86_64-linux.legacy-home = { };
        den.homes."flat-home" = {
          system = "x86_64-linux";
        };

        expr = builtins.sort (a: b: a < b) (builtins.attrNames den.homes.x86_64-linux);
        expected = [
          "flat-home"
          "legacy-home"
        ];
      }
    );

    test-flat-home-cross-entity-host-lookup = denTest (
      { den, config, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.homes."tux@igloo" = {
          system = "x86_64-linux";
        };

        den.aspects.igloo.nixos.networking.hostName = "igloo";
        den.aspects.tux.includes = [ den.provides.define-user ];
        den.aspects.tux.homeManager =
          { osConfig, ... }:
          {
            home.keyboard.model = osConfig.networking.hostName;
          };

        expr = config.flake.homeConfigurations."tux@igloo".config.home.keyboard.model;
        expected = "igloo";
      }
    );

    test-flat-home-output = denTest (
      { den, config, ... }:
      {
        den.homes."tux" = {
          system = "x86_64-linux";
        };
        den.default.homeManager.home.stateVersion = "25.11";
        den.default.includes = [ den.provides.define-user ];
        den.aspects.tux.homeManager.programs.fish.enable = true;

        expr = config.flake.homeConfigurations.tux.config.programs.fish.enable;
        expected = true;
      }
    );
  };
}
