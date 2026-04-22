{ lib, den, ... }:
let
  stageSubmodule = lib.types.submodule {
    imports = den.lib.aspects.types.aspectType.getSubModules;
    # No options.into — stages don't define transitions
    # No options.__functor — stages aren't callable
  };

  stageTreeType = lib.types.mkOptionType {
    name = "stageTree";
    description = "stage definition or namespace";
    check = lib.isAttrs;
    merge =
      loc: defs:
      let
        stageNodeKeys = [
          "_"
          "includes"
          "provides"
          "_module"
        ];
        hasKey = x: builtins.any (k: x ? ${k}) stageNodeKeys;
        isLeaf = lib.any (d: hasKey d.value) defs;
      in
      if isLeaf then
        stageSubmodule.merge loc defs
      else
        (lib.types.lazyAttrsOf stageTreeType).merge loc defs;
    emptyValue = {
      value = { };
    };
  };
in
{
  inherit stageTreeType;
}
