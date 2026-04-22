{ denTest, ... }:
{
  flake.tests.home-manager-use-global-pkgs = {

    test-enabled = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        # hm-host context is activated when host has HM support
        den.stages.hm-host.nixos.home-manager.useGlobalPkgs = true;
        den.stages.hm-host.includes = [ ];

        expr = igloo.home-manager.useGlobalPkgs;
        expected = true;
      }
    );

    test-disabled = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        expr = igloo.home-manager.useGlobalPkgs;
        expected = false;
      }
    );

    test-not-activated-without-hm-users = denTest (
      { den, config, ... }:
      {
        den.hosts.x86_64-linux.igloo = { };
        den.stages.hm-host.nixos.home-manager.useGlobalPkgs = true;
        den.stages.hm-host.includes = [ ];

        expr = config.flake.nixosConfigurations.igloo.config ? home-manager;
        expected = false;
      }
    );

  };
}
