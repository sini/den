{
  lib,
  den,
  fx,
  ...
}:
let
  includeIf = guardFn: aspects: {
    name = "<includeIf>";
    meta = {
      conditional = true;
      guard = guardFn;
      aspects = aspects;
    };
    includes = [ ];
  };

  # TODO: Transitive includes — include all provides from an aspect.
  # Design spec pending. Usage: includes = [ (includeAll foo.provides) ];
  # includeAll = provides: { ... };

in
{
  inherit includeIf;
}
