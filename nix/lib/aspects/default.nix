{
  lib,
  den,
  inputs,
  ...
}:
let
  rawTypes = import ./types.nix { inherit den lib; };
  hasAspect = import ./has-aspect.nix { inherit den lib; };
  fx = import ./fx { inherit den lib; };

  fxResolveTree =
    class: resolved:
    let
      isBareFn = lib.isFunction resolved && !builtins.isAttrs resolved;
      # Only explicitly parametric functor attrsets need wrapping.
      isFunctor =
        !isBareFn
        && builtins.isAttrs resolved
        && resolved ? __functor
        && builtins.isFunction (resolved.__functor resolved);
      functorArgs = if isFunctor then builtins.functionArgs (resolved.__functor resolved) else { };
      needsWrap = isFunctor && functorArgs != { };
      bareFnArgs = if isBareFn then lib.functionArgs resolved else { };
      isModuleFn =
        isBareFn
        && den.lib.canTake.upTo {
          lib = true;
          config = true;
          options = true;
        } resolved;
      wrapped =
        if isModuleFn then
          den.lib.aspects.types.aspectType.merge
            [ "<bare-module>" ]
            [
              {
                file = "<bare-module>";
                value = resolved;
              }
            ]
        else if isBareFn then
          {
            __fn = resolved;
            __args = bareFnArgs;
            name = "<bare-fn>";
            meta = { };
          }
        else if needsWrap then
          {
            __fn = resolved.__functor resolved;
            __args = functorArgs;
            name = resolved.name or "<function body>";
            meta = resolved.meta or { };
            includes = resolved.includes or [ ];
          }
          // lib.optionalAttrs (resolved ? __scopeHandlers) { inherit (resolved) __scopeHandlers; }
        else
          resolved;
      # Extract __ctx from ctxApply-tagged aspects. Seeds state.currentCtx
      # so into functions receive the initial context values. Parametric arg
      # resolution uses __scopeHandlers instead.
      ctx = resolved.__ctx or { };
    in
    fx.pipeline.fxResolve {
      inherit class ctx;
      self = wrapped;
    };

  types = lib.mapAttrs (_: v: v { }) rawTypes;
in
{
  inherit types fx;
  resolve = fxResolveTree;
  inherit (hasAspect) hasAspectIn collectPathSet mkEntityHasAspect;
  mkAspectsType = cnf': lib.mapAttrs (_: v: v cnf') rawTypes;
  # Predicates exported directly (not through types mapAttrs which applies { } to each value).
  inherit (rawTypes) isParametricWrapper isSubmoduleFn isMeaningfulName;
}
