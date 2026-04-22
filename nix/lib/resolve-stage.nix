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

  # Synthesize relationships into an into-style function for a given stage name.
  # Mirrors the synthesis in mkPipeline so child aspects (not just roots) get
  # relationship-driven transitions.
  synthesizeRelationships =
    stageName:
    let
      relationships = den.relationships or { };
      matchingRels = lib.filter (rel: rel.from == stageName) (builtins.attrValues relationships);
    in
    if matchingRels == [ ] then
      null
    else
      rCtx:
      builtins.foldl' (
        acc: rel:
        let
          targets = rel.resolve rCtx;
          targetList = if builtins.isList targets then targets else [ targets ];
        in
        if targetList == [ ] then acc else acc // { ${rel.to} = (acc.${rel.to} or [ ]) ++ targetList; }
      ) { } matchingRels;

  resolveStage =
    name: ctx:
    let
      stageNode = den.stages.${name} or { };
      # Fallback to ctx node during transition
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

      # Merge ctx into with relationship transitions
      existingInto = ctxNode.into or null;
      relationshipInto = synthesizeRelationships name;
      mergedInto =
        if existingInto != null && relationshipInto != null then
          rCtx:
          let
            existing = existingInto rCtx;
            fromRels = relationshipInto rCtx;
          in
          existing // (builtins.removeAttrs fromRels (builtins.attrNames existing))
        else if relationshipInto != null then
          relationshipInto
        else if existingInto != null then
          existingInto
        else
          _: { };
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
        into = mergedInto;
      };
      provides = (ctxNode.provides or { }) // (stageNode.provides or { });
      includes = (ctxNode.includes or [ ]) ++ (stageNode.includes or [ ]);
      __ctx = ctx;
      __scopeHandlers = scopeHandlers;
    };
in
resolveStage
