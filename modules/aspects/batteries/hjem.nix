{
  den,
  inputs,
  ...
}:
let
  inherit (den.lib.home-env) makeHomeEnv;

  result = makeHomeEnv {
    className = "hjem";
    optionPath = "hjem";
    getModule =
      { host, ... }:
      if inputs ? hjem then
        inputs.hjem."${host.class}Modules".default
      else
        throw "den: hjem battery requires inputs.hjem — add hjem to your flake inputs or set den.hosts.<system>.<name>.hjem.module explicitly";
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
  den.schema.host.imports = [ result.hostConf ];
  den.schema.host.includes = [ result.battery ];

  den.schema.user.includes = [ result.userDetect ];

  den.classes.hjem.description = "Hjem user environment";
}
