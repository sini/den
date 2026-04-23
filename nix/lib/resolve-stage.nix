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
          synth = den.lib.synthesizePolicies name;
          stageInto = stageNode.meta.into or null;
          # Merge stage-declared into with synthesized policies.
          into =
            if stageInto != null && synth != null then
              rCtx:
              let
                fromStage = stageInto rCtx;
                fromPolicies = synth rCtx;
              in
              fromStage // (builtins.removeAttrs fromPolicies (builtins.attrNames fromStage))
            else if stageInto != null then
              stageInto
            else if synth != null then
              synth
            else
              _: { };
        in
        {
          handleWith = null;
          excludes = [ ];
          provider = [ ];
          inherit into;
        };
      provides = stageNode.provides or { };
      includes = stageNode.includes or [ ];
      __ctx = ctx;
      __scopeHandlers = scopeHandlers;
    };
in
resolveStage
