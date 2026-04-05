{
  lib,
  den,
  ...
}:
let
  defaultFunctor = (den.lib.parametric { }).__functor;
  typesConf = { inherit defaultFunctor; };
  rawTypes = import ./types.nix { inherit den lib; };
  types = lib.mapAttrs (_: v: v typesConf) rawTypes;
  mkAspectsType = rawTypes.aspectsType;
  resolveModule = import ./resolve.nix { inherit lib; };
  allTransforms = import ./transforms.nix { inherit lib; };
in
{
  inherit types mkAspectsType;
  inherit (allTransforms) toAspectPath;
  inherit (resolveModule) resolve resolve';
  transforms = { inherit (allTransforms) exclude substitute; };
}
