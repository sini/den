# ctxApply — the __functor of ctx nodes.
#
# Called as: den.ctx.host { host = config; }
# Returns an aspect-shaped attrset preserving into/provides for
# the fx pipeline's transitionHandler and emitSelfProvide to handle.
#
# __ctx carries the initial context value to the pipeline entry point
# (fxResolveTree extracts it for defaultHandlers).
# __scopeHandlers carries handler data so aspectToEffect can derive
# scope.provide at point of use for parametric arg resolution.
{ lib, den, ... }:
let
  fx = den.lib.fx;
  inherit (den.lib.aspects.fx.handlers) constantHandler;
  # Stage behavior is merged into ctx nodes at ctxApply time so that
  # direct calls like den.ctx.user { host; user; } (e.g. from home-env.nix)
  # also pick up den.stages.user.includes, not just the transition path.
  stages = den.stages or { };
in
_ctxNs:
let
  # Structural keys that ctxApply always forwards.
  structuralKeys = [
    "name"
    "description"
    "meta"
    "includes"
    "provides"
    "into"
    "__functor"
    "__parametricResolved"
    "_module"
  ];

  ctxApply =
    self: ctx:
    let
      meta = self.meta or { };
      # Preserve class keys (nixos, homeManager, funny, etc.) from the
      # ctx node definition — these are emitted by compileStatic.
      classAttrs = builtins.removeAttrs self structuralKeys;
      # Merge stage includes so den.stages.X.includes is honoured on direct
      # ctxApply calls (not only on transition-handler paths).
      stageName = self.name or "";
      stageNode = if stageName != "" then stages.${stageName} or null else null;
      stageIncludes = if stageNode != null then stageNode.includes or [ ] else [ ];
      # Merge stage class keys (nixos, funny, etc.) alongside ctx class keys.
      # Stage keys are wrapped as an include (not shallow //) to preserve both.
      stageClassAttrs =
        if stageNode != null then
          builtins.removeAttrs stageNode [
            "includes"
            "name"
            "description"
            "meta"
            "provides"
            "_module"
            "_"
          ]
        else
          { };
      stageAsInclude =
        if stageClassAttrs != { } then
          [
            (
              stageClassAttrs
              // {
                name = "${stageName}.stage";
                includes = stageIncludes;
              }
            )
          ]
        else
          stageIncludes;
    in
    classAttrs
    // {
      name = self.name or "<anon>";
      meta = {
        handleWith = meta.handleWith or null;
        excludes = meta.excludes or [ ];
        provider = meta.provider or [ ];
      };
      # Preserve for the pipeline to handle natively:
      # - into: transitionHandler evaluates with currentCtx, recurses into target ctx nodes
      # - provides: emitSelfProvide handles provides.${self.name}
      # - includes: emitIncludes processes child aspects
      # Store into in meta — the raw function survives aspectSubmodule's
      # freeform (deferredModule) which would wrap it as a module.
      meta.into = self.into or (_: { });
      provides = self.provides or { };
      includes = (self.includes or [ ]) ++ stageAsInclude;
      # Carry context to the pipeline entry point (seeds state.currentCtx
      # for into functions). __scopeHandlers handles parametric arg resolution.
      __ctx = ctx;
      __scopeHandlers = constantHandler ctx;
    };
in
ctxApply
