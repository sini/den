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

  # Nest a module at a path by REFERENCE, keeping the collected module wrapper
  # INTACT. Unlike nestPlain (which unwraps `mod.imports` and pre-evaluates the
  # content in an isolated freeform evalModules, freezing it to resolved config),
  # this preserves the wrapper's `key`/`_file` (assigned by wrap-classes.nix as
  # `<class>@<identity>`) and delivers the module unevaluated. Required when the
  # target RE-INSTANTIATES the delivered content as its own NixOS system (e.g.
  # microvm `microvm.vms.<n>.config`, whose option type re-runs eval-config with
  # the full base module-list): the target then applies base-module defaults AND
  # dedups identical re-declarations across {host,user} scopes by `key` — exactly
  # as spawn-node's instantiation walk does. Pre-evaluating (nestPlain) instead
  # strips base defaults and drops the keys, poisoning every namespace aggregate
  # and double-declaring keyless modules at the target.
  nestVerbatim = path: mod: {
    config = lib.setAttrByPath path { imports = [ mod ]; };
  };

  # Nest a module at a target path (dispatch between verbatim, adapt, and plain
  # strategies). `reinstantiate` selects verbatim delivery for targets that
  # re-evaluate the payload as their own module set.
  nestModule =
    path: adaptArgs: reinstantiate: mod:
    if path == [ ] then
      mod
    else if reinstantiate then
      nestVerbatim path mod
    else if adaptArgs != null then
      nestWithAdaptArgs path adaptArgs mod
    else
      nestPlain path mod;

  # Wrap a module with a conditional guard.
  #
  # A bool guard gates content with `lib.optionalAttrs`, not `lib.mkIf`, to
  # match the forward path (forward.nix guardFn): a false guard must contribute
  # *nothing* — `mkIf false` still requires the target option to exist, so an
  # empty-path route into an undeclared option would fail option type-checking
  # even when skipped. `optionalAttrs false` drops the subtree entirely.
  #
  # A structural module (carries `imports`/`_file`/`key` module metadata but no
  # flat `config`) cannot be merged under `config` — its module-level keys would
  # be mis-read as option definitions and fail (e.g. "the option `_file' does
  # not exist"). This is the empty-path case, where the source is the raw
  # collector module. Recurse into its `imports`, gating each leaf's config and
  # leaving module metadata at module level.
  guardModule =
    guard: mod:
    if guard == null then
      mod
    else
      let
        guardOne =
          node: args:
          let
            inner = if builtins.isFunction node then node args else node;
          in
          if inner ? imports && !(inner ? config) then
            { imports = map guardOne inner.imports; } // builtins.removeAttrs inner [ "imports" ]
          else
            { config = lib.optionalAttrs (guard args) (inner.config or inner); };
      in
      guardOne mod;

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
      reinstantiate ? false,
    }:
    let
      adapted = map (adaptModule adaptArgs path) modules;
    in
    if adapted == [ ] then
      [ ]
    # reinstantiate keeps each collected wrapper keyed and separate so the
    # target's own evalModules dedups them; it must not be combined into one
    # adaptArgs evalModules.
    else if adaptArgs != null && path != [ ] && !reinstantiate then
      [ (guardModule guard (nestWithAdaptArgs path adaptArgs { imports = adapted; })) ]
    else
      map (mod: guardModule guard (nestModule path adaptArgs reinstantiate mod)) adapted;

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
