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
  ];

  # Synthesize relationships into an into-style function for a given stage name.
  synthesizeRelationships =
    stageName:
    let
      relationships = den.relationships or { };
      matchingRels = lib.filter (rel: rel.from == stageName) (builtins.attrValues relationships);
    in
    if matchingRels == [ ] then
      _: { }
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
        into = synthesizeRelationships name;
      };
      provides = stageNode.provides or { };
      includes = stageNode.includes or [ ];
      __ctx = ctx;
      __scopeHandlers = scopeHandlers;
    };
in
resolveStage
