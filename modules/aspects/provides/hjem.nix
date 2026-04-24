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
    className = "hjem";
    optionPath = "hjem";
    getModule = { host, ... }: inputs.hjem."${host.class}Modules".default;
    forwardPathFn =
      { user, ... }:
      [
        "hjem"
        "users"
        user.userName
      ];
  };

in
{
  den.stages = result.stages;
  den.schema.host.imports = [ result.hostConf ];

  den.policies = {
    host-to-hjem-host = {
      from = "host";
      to = "hjem-host";
      resolve = mkDetectHost {
        className = "hjem";
        optionPath = "hjem";
      };
    };

    hjem-host-to-hjem-user = {
      from = "hjem-host";
      to = "hjem-user";
      resolve = mkIntoClassUsers "hjem";
    };
  };
}
