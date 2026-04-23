# synthesizeRelationships — shared helper.
# Filters den.relationships by `from == stageName`, folds matching rels,
# and builds { ${rel.to} = [...] }.
# Returns null when no relationships match (callers decide default).
{
  lib,
  den,
  ...
}:
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
  ) { } matchingRels
