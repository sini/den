{ inputs, den, ... }:
{
  systems = builtins.attrNames den.hosts;

  imports = [
    inputs.den.flakeModule
    inputs.den.flakeModules.fxPipeline
    inputs.files.flakeModules.default
  ];
}
