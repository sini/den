# Returns null when no policies match (callers decide default).
{
  lib,
  den,
  ...
}:
let
  synthesize =
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
      ) { } matching;

  # Merge an existing into function with synthesized policies for a stage.
  # Existing into takes priority — policies fill in new target keys.
  mergePolicyInto =
    stageName: existingInto:
    let
      policyInto = synthesize stageName;
    in
    if existingInto != null && policyInto != null then
      rCtx:
      let
        existing = existingInto rCtx;
        fromPolicies = policyInto rCtx;
      in
      existing // (builtins.removeAttrs fromPolicies (builtins.attrNames existing))
    else if existingInto != null then
      existingInto
    else
      policyInto;
in
{
  inherit synthesize mergePolicyInto;
}
