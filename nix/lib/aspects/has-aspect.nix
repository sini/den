# Query whether an aspect is structurally present in a resolved tree.
# Entity-facing wiring lives in modules/context/has-aspect.nix.
{ lib, den, ... }:
let
  inherit (den.lib.aspects.fx) identity;
  inherit (identity) aspectPath pathKey;

  refKey =
    ref:
    if (ref ? name) && (ref ? meta) then
      pathKey (aspectPath ref)
    else
      throw "hasAspect: ref must have both `name` and `meta` (got ${builtins.typeOf ref}).";

  # Resolve tree via fx pipeline and extract pathSet from state.
  # Inlines the same root normalization as fxResolveTree (default.nix)
  # to handle raw lambdas and functor attrsets.
  collectPathSet =
    { tree, class }:
    let
      normalized = den.lib.aspects.normalizeRoot tree;
      result = den.lib.aspects.fx.pipeline.fxFullResolve {
        inherit class;
        ctx = normalized.__ctx or tree.__ctx or { };
        self = normalized;
      };
    in
    result.state.pathSet or { };

  hasAspectIn =
    {
      tree,
      class,
      ref,
    }:
    (collectPathSet { inherit tree class; }) ? ${refKey ref};

  mkEntityHasAspect =
    {
      tree,
      primaryClass,
      classes,
    }:
    let
      setFor = builtins.listToAttrs (
        map (c: {
          name = c;
          value = collectPathSet {
            inherit tree;
            class = c;
          };
        }) (lib.unique ([ primaryClass ] ++ classes))
      );
      check = class: ref: (setFor.${class} or { }) ? ${refKey ref};
      bareFn = check primaryClass;
    in
    {
      __functor = _: bareFn;
      forClass = check;
      forAnyClass = ref: lib.any (c: check c ref) classes;
    };

in
{
  inherit
    hasAspectIn
    collectPathSet
    mkEntityHasAspect
    ;
}
