{
  den,
  inputs,
  ...
}:
let
  inherit (den.lib.home-env) makeHomeEnv;

  result = makeHomeEnv {
    className = "maid";
    supportedOses = [ "nixos" ];
    optionPath = "nix-maid";
    getModule =
      { host, ... }:
      if inputs ? nix-maid then
        inputs.nix-maid."${host.class}Modules".default
      else
        throw "den: maid battery requires inputs.nix-maid — add nix-maid to your flake inputs or set den.hosts.<system>.<name>.nix-maid.module explicitly";
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
  den.schema.host.imports = [ result.hostConf ];
  den.schema.host.includes = [ result.battery ];

  den.schema.user.includes = [ result.userDetect ];

  den.classes.maid.description = "nix-maid user environment";
}
