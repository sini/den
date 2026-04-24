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
    check = v: lib.isAttrs v || builtins.isFunction v;
    merge =
      loc: defs:
      let
        name = lib.last loc;
        # Coerce bare functions: den.stages.foo = { host }: ...
        # becomes den.stages.foo.provides.foo = { host }: ...
        coerced = map (
          d:
          if builtins.isFunction d.value then
            d
            // {
              value = {
                provides.${name} = d.value;
              };
            }
          else
            d
        ) defs;
        stageNodeKeys = [
          "_"
          "includes"
          "provides"
          "_module"
        ];
        hasKey = x: builtins.any (k: x ? ${k}) stageNodeKeys;
        isLeaf = lib.any (d: hasKey d.value) coerced;
      in
      if isLeaf then
        stageSubmodule.merge loc coerced
      else
        (lib.types.lazyAttrsOf stageTreeType).merge loc coerced;
  };
in
{
  inherit stageSubmodule stageTreeType;
}
