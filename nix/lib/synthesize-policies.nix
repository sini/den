# Returns null when no policies match (callers decide default).
{
  lib,
  den,
  ...
}:
let
  # Infer the required entity key from a stage name.
  # from = "host" or "hm-host" implies ctx.host must be an attrset entity.
  # from = "user" or "hm-user" implies ctx.user must be an attrset entity.
  # from = "home" implies ctx.home must be an attrset entity.
  # Other stages (flake, flake-system, etc.) have no entity requirement.
  entityKeyFor =
    stage:
    if stage == "host" || lib.hasSuffix "-host" stage then
      "host"
    else if stage == "user" || lib.hasSuffix "-user" stage then
      "user"
    else if stage == "home" then
      "home"
    else
      null;

  # Check if context satisfies the entity requirement implied by the stage.
  # When the entity key is present but not an attrset (e.g., host = "igloo"
  # string from aspect name), the policy is skipped — its resolve function
  # can safely destructure { host, ... } without guards.
  ctxSatisfiesEntity =
    stage: ctx:
    let
      key = entityKeyFor stage;
    in
    key == null || (ctx ? ${key} && builtins.isAttrs ctx.${key});

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
          targets = if ctxSatisfiesEntity policy.from rCtx then policy.resolve rCtx else [ ];
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
