# Returns null when no policies match (callers decide default).
{
  lib,
  den,
  ...
}:
stageName:
let
  policies = den.policies or { };
  matching = lib.filter (policy: policy.from == stageName) (builtins.attrValues policies);
in
if matching == [ ] then
  null
else
  rCtx:
  builtins.foldl' (
    acc: policy:
    let
      targets = policy.resolve rCtx;
      targetList = if builtins.isList targets then targets else [ targets ];
    in
    if targetList == [ ] then
      acc
    else
      acc // { ${policy.to} = (acc.${policy.to} or [ ]) ++ targetList; }
  ) { } matching
