# Route module wrapping — path nesting, guards, adaptArgs.
{ lib, ... }:
let
  # Freeform type for route nesting evalModules: merges like NixOS
  # (attrsets deep-merge, lists concatenate) but errors on conflicting
  # scalar or derivation values instead of silently clobbering.
  mergeableType = lib.mkOptionType {
    name = "mergeable";
    description = "auto-merged value (attrsets merge, lists concatenate, scalars conflict)";
    merge =
      loc: defs:
      let
        values = map (d: d.value) defs;
        first = builtins.head values;
        allLists = builtins.all builtins.isList values;
        # Derivations are attrsets but must not deep-merge — treat as opaque.
        allMergeableAttrs = builtins.all (v: builtins.isAttrs v && !(lib.isDerivation v)) values;
      in
      if builtins.length defs == 1 then
        first
      else if allLists then
        builtins.concatLists values
      else if allMergeableAttrs then
        (lib.types.lazyAttrsOf mergeableType).merge loc defs
      else
        throw "den: the option `${lib.showOption loc}' has conflicting definitions from multiple aspects";
  };
  nestingFreeformType = lib.types.lazyAttrsOf mergeableType;

  # Adapt a module's args when path is empty (top-level adaptArgs).
  adaptModule =
    adaptArgs: path: mod:
    if adaptArgs == null || path != [ ] then
      mod
    else if builtins.isFunction mod then
      args: mod (adaptArgs args)
    else
      mod;

  # Nest a module at a path using submodule evaluation with adapted specialArgs.
  nestWithAdaptArgs =
    path: adaptArgs: mod: args:
    let
      fullArgs = args // (args.config._module.args or { });
      adapted = adaptArgs fullArgs;
      sourceModules = if builtins.isAttrs mod && mod ? imports then mod.imports else [ mod ];
      evaluated = lib.evalModules {
        specialArgs = adapted;
        modules = [
          { config._module.freeformType = nestingFreeformType; }
        ]
        ++ sourceModules;
      };
    in
    {
      config = lib.setAttrByPath path (
        builtins.removeAttrs evaluated.config [
          "_module"
          "warnings"
          "assertions"
        ]
      );
    };

  # Nest a module at a path by evaluating imports with full outer args.
  # Uses evalModules with raw freeform type so conflicting keys error
  # instead of silently clobbering via recursiveUpdate.
  nestPlain =
    path: mod: args:
    let
      fullArgs = args // (args.config._module.args or { });
      resolveImport = imp: if builtins.isFunction imp then imp fullArgs else imp;
      sourceModules = if builtins.isAttrs mod && mod ? imports then mod.imports else [ mod ];
      resolved = map resolveImport sourceModules;
      evaluated = lib.evalModules {
        specialArgs = fullArgs;
        modules = [
          { config._module.freeformType = nestingFreeformType; }
        ]
        ++ resolved;
      };
    in
    {
      config = lib.setAttrByPath path (
        builtins.removeAttrs evaluated.config [
          "_module"
          "warnings"
          "assertions"
        ]
      );
    };

  # Nest a module at a target path (dispatch between adapt and plain strategies).
  nestModule =
    path: adaptArgs: mod:
    if path == [ ] then
      mod
    else if adaptArgs != null then
      nestWithAdaptArgs path adaptArgs mod
    else
      nestPlain path mod;

  # Wrap a module with a conditional guard.
  guardModule =
    guard: mod:
    if guard == null then
      mod
    else
      args:
      let
        inner = if builtins.isFunction mod then mod args else mod;
      in
      {
        config = lib.mkIf (guard args) (inner.config or inner);
      };

  # Apply the adapt → nest → guard pipeline to a list of modules.
  # When adaptArgs is non-null (nestWithAdaptArgs path), all modules are
  # combined into a single evalModules call so that multiple aspects
  # emitting to the same class merge correctly inside evalModules,
  # rather than producing separate config definitions that get
  # shallow-merged by the freeform `unspecified` type.  (#572)
  wrapRouteModules =
    {
      modules,
      path,
      guard ? null,
      adaptArgs ? null,
    }:
    let
      adapted = map (adaptModule adaptArgs path) modules;
    in
    if adapted == [ ] then
      [ ]
    else if adaptArgs != null && path != [ ] then
      [ (guardModule guard (nestWithAdaptArgs path adaptArgs { imports = adapted; })) ]
    else
      map (mod: guardModule guard (nestModule path adaptArgs mod)) adapted;

  # Collect class modules from a forward aspect (recursing into includes).
  collectClassMods =
    cls: aspect:
    let
      own = lib.optional (aspect ? ${cls}) aspect.${cls};
      nested = builtins.concatMap (collectClassMods cls) (aspect.includes or [ ]);
    in
    own ++ nested;
in
{
  inherit wrapRouteModules collectClassMods;
}
