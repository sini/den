# resolveStage — replacement for ctxApply.
# Builds an aspect-shaped attrset from a stage node + context.
# Does not use __functor — plain function call.
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
  ];

  resolveStage =
    name: ctx:
    let
      stageNode = den.stages.${name} or { };
      # Fallback to ctx node for provides during transition
      ctxNode = (den.ctx or { }).${name} or { };
      classAttrs = builtins.removeAttrs stageNode structuralKeys;
      ctxClassAttrs = builtins.removeAttrs ctxNode (
        structuralKeys
        ++ [
          "into"
          "__functor"
        ]
      );
      scopeHandlers = constantHandler ctx;
    in
    # Merge: ctx class keys as base, stage class keys override
    ctxClassAttrs
    // classAttrs
    // {
      name = stageNode.name or ctxNode.name or name;
      meta = {
        handleWith = null;
        excludes = [ ];
        provider = [ ];
        # Carry ctx into during transition — pipeline synthesis merges with relationships
        into = ctxNode.into or (_: { });
      };
      provides = (ctxNode.provides or { }) // (stageNode.provides or { });
      includes = (ctxNode.includes or [ ]) ++ (stageNode.includes or [ ]);
      __ctx = ctx;
      __scopeHandlers = scopeHandlers;
    };
in
resolveStage
