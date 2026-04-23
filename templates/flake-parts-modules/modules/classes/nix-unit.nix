{ inputs, config, ... }:
{
  imports = [ inputs.nix-unit.modules.flake.default ];

  # some globals
  perSystem.nix-unit = {
    allowNetwork = true;
    inputs = inputs;
  };

  den.policies.flake-parts-to-flake-parts-system-tests = {
    from = "flake-parts";
    to = "flake-parts-system";
    resolve = _: [
      {
        fromClass = _: "tests";
        intoPath = _: [
          "nix-unit"
          "tests"
        ];
        # test helpers
        adaptArgs =
          args:
          let
            igloo = config.flake.nixosConfigurations.igloo.config;
            tux = igloo.users.users.tux;
          in
          args.config.allModuleArgs // { inherit igloo tux; };
      }
    ];
  };
}
