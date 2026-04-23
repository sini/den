# resolveStage — pipeline entry point.
# Builds an aspect-shaped attrset from a stage node + context.
# Synthesizes relationships for transitions.
{
  lib,
  den,
  ...
}:
let
  inherit (den.lib.aspects.fx.handlers) constantHandler;

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
      meta = {
        handleWith = null;
        excludes = [ ];
        provider = [ ];
        into =
          let
            synth = den.lib.synthesizeRelationships name;
          in
          if synth != null then synth else _: { };
      };
      provides = stageNode.provides or { };
      includes = stageNode.includes or [ ];
      __ctx = ctx;
      __scopeHandlers = scopeHandlers;
    };
in
resolveStage
