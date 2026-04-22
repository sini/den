{
  den,
  lib,
  inputs,
  ...
}:
let
  inherit (den.lib.home-env) makeHomeEnv;

  result = makeHomeEnv {
    className = "homeManager";
    ctxName = "hm";
    optionPath = "home-manager";
    getModule = { host, ... }: inputs.home-manager."${host.class}Modules".home-manager;
    forwardPathFn =
      { user, ... }:
      [
        "home-manager"
        "users"
        user.userName
      ];
  };

  homeCtx = {
    home.into.default = lib.singleton;
  };

in
{
  den.ctx = result.ctx // homeCtx;
  den.stages = result.stages // {
    home.provides.home = { home }: home.aspect;
  };
  den.schema.host.imports = [ result.hostConf ];
}
