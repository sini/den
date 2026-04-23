{
  lib,
  den,
  ...
}:
let
  inherit (den.lib.aspects.fx.handlers) constantHandler;

  # Stage nodes lack pipeline-internal keys (__fn, __args, __scopeHandlers, etc.)
  # that aspect.nix's structuralKeysSet includes, so this list is shorter.
  structuralKeys = [
    "name"
    "description"
    "meta"
    "includes"
    "provides"
    "_module"
    "_"
    "__functor"
  ];

  resolveStage =
    name: ctx:
    let
      stageNode = den.stages.${name} or { };
      classAttrs = builtins.removeAttrs stageNode structuralKeys;
      scopeHandlers = constantHandler ctx;
    in
    classAttrs
    // {
      name = stageNode.name or name;
      meta =
        let
          stageInto = stageNode.meta.into or null;
          into = den.lib.synthesizePolicies.mergePolicyInto name stageInto;
        in
        {
          handleWith = null;
          excludes = [ ];
          provider = [ ];
          into = if into != null then into else _: { };
        };
      provides = stageNode.provides or { };
      includes = stageNode.includes or [ ];
      __ctx = ctx;
      __scopeHandlers = scopeHandlers;
    };
in
resolveStage
