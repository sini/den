{ inputs, den, ... }:
{
  systems = builtins.attrNames den.hosts;

  imports = [
    inputs.files.flakeModules.default
  ];
}
