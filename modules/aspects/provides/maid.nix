{
  den,
  lib,
  inputs,
  ...
}:
let
  inherit (den.lib.home-env) makeHomeEnv;

  mkDetectHost =
    {
      className,
      supportedOses ? [
        "nixos"
        "darwin"
      ],
      optionPath,
    }:
    { host, ... }:
    let
      isOsSupported = builtins.elem host.class supportedOses;
      isEnabled = (host.${optionPath} or { }).enable or false;
      hostHasClass = builtins.any (user: lib.elem className user.classes) (lib.attrValues host.users);
    in
    lib.optional (isEnabled && isOsSupported && hostHasClass) { inherit host; };

  mkIntoClassUsers =
    className:
    { host, ... }:
    map (user: { inherit host user; }) (
      lib.filter (u: lib.elem className u.classes) (lib.attrValues host.users)
    );

  result = makeHomeEnv {
    className = "maid";
    supportedOses = [ "nixos" ];
    optionPath = "nix-maid";
    getModule = { host, ... }: inputs.nix-maid."${host.class}Modules".default;
    forwardPathFn =
      { user, ... }:
      [
        "users"
        "users"
        user.userName
        "maid"
      ];
  };

in
{
  den.stages = result.stages;
  den.schema.host.imports = [ result.hostConf ];

  den.policies = {
    host-to-maid-host = {
      from = "host";
      to = "maid-host";
      resolve = mkDetectHost {
        className = "maid";
        supportedOses = [ "nixos" ];
        optionPath = "nix-maid";
      };
    };

    maid-host-to-maid-user = {
      from = "maid-host";
      to = "maid-user";
      resolve = mkIntoClassUsers "maid";
    };
  };
}
