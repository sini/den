# ctxApply — the __functor of ctx nodes.
#
# Called as: den.ctx.host { host = config; }
# Returns an aspect-shaped attrset preserving into/provides for
# the fx pipeline's transitionHandler and emitSelfProvide to handle.
#
# __ctx carries the initial context value to the pipeline entry point
# (fxResolveTree extracts it for defaultHandlers).
# __scope carries a handler-closure (scope.stateful partially applied)
# so aspectToEffect can resolve parametric args in separate pipeline runs.
{ lib, den, ... }:
let
  fx = den.lib.fx;
  inherit (den.lib.aspects.fx.handlers) constantHandler;
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
      includes = self.includes or [ ];
      # Carry context to the pipeline entry point (seeds state.currentCtx
      # for into functions). __scope handles parametric arg resolution.
      __ctx = ctx;
      __scope = fx.effects.scope.provide (constantHandler ctx);
      __scopeHandlers = constantHandler ctx;
    };
in
ctxApply
