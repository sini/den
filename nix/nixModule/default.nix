{
  den-lib,
  config,
  lib,
  inputs,
  ...
}@args:
{
  _module.args.den = config.den;
  imports = map (f: import f (args // { den = config.den; })) [
    ./lib.nix
    ./stages.nix
    ./relationships.nix
    ./aspects.nix
  ];
}
