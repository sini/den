# Handles: resolve-schema-entity
# Entity resolution: push scope, resolve entity, propagate forwards, pop scope.
# Deferred includes are NOT refired here — entity-kind args are classified
# synchronously in bind (fan-out/inert/ctx). Non-entity deferred includes are
# drained post-pipeline (resolve.nix baseDrain) or on context-widen.
{
  lib,
  den,
  ...
}:
let
  inherit (den.lib) fx;
  inherit (den.lib.aspects.fx) identity;

  # Strip stale __ctxId from aspects (prevents identity mismatches in fresh scope).
  stripCtxId =
    a:
    if builtins.isAttrs a then
      (builtins.removeAttrs a [ "__ctxId" ])
      // lib.optionalAttrs (a ? includes) { includes = map stripCtxId (a.includes or [ ]); }
    else
      a;

  # Merge policy/resolve includes into raw entity.
  mergeEntityIncludes =
    rawEntity: includeAspects: policyIncludes: resolveIncludes:
    rawEntity
    // {
      includes =
        (rawEntity.includes or [ ])
        ++ map stripCtxId includeAspects
        ++ map stripCtxId policyIncludes
        ++ map stripCtxId resolveIncludes;
    };

  # Resolve entity tree within scope: resolve-entity → resolve → propagate → pop.
  resolveEntityInScope =
    scopeHandlersForCtx: scopedCtx: param: prevResults: scopeId: parentScope:
    fx.effects.scope.provide scopeHandlersForCtx (
      fx.bind (fx.send "resolve-entity" { kind = param.targetKind; }) (
        rawEntity:
        let
          entity =
            mergeEntityIncludes rawEntity param.includeAspects param.policyIncludes
              param.resolveIncludes;
        in
        fx.bind
          (fx.send "resolve" {
            aspect = entity;
            identity = identity.key entity;
            ctx = scopedCtx;
            gated = true;
          })
          (
            resolvedList:
            let
              childResult = builtins.head resolvedList;
              allResults = prevResults ++ [ childResult ];
            in
            fx.bind (fx.send "propagate-routes" { inherit scopeId; }) (
              _: fx.bind (fx.send "restore-scope" { inherit parentScope; }) (_: fx.pure allResults)
            )
          )
      )
    );

  resolveSchemaEntityHandler = {
    "resolve-schema-entity" =
      { param, state }:
      let
        parentScope = state.currentScope;
      in
      {
        resume =
          fx.bind
            (fx.send "push-scope" {
              inherit (param) scopedCtx entityClass;
              inherit parentScope;
              sourcePolicyName = param.sourcePolicyName or null;
              entityKind = param.targetKind or null;
            })
            (
              pushResult:
              resolveEntityInScope pushResult.scopeHandlers param.scopedCtx param param.prevResults
                pushResult.scopeId
                parentScope
            );
        inherit state;
      };
  };

in
{
  inherit resolveSchemaEntityHandler;
}
