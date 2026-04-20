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
      isFunctor = !isBareFn && builtins.isAttrs resolved && resolved ? __functor;
      functorArgs = if isFunctor then builtins.functionArgs (resolved.__functor resolved) else { };
      needsWrap = isFunctor && functorArgs != { };
      bareFnArgs = if isBareFn then lib.functionArgs resolved else { };
      # NixOS module functions are deferred modules, not parametric aspects.
      # Heuristic: any function accepting ONLY module-system args (lib, config,
      # options) is treated as a module. Functions with extra args (host, user)
      # are parametric. Edge case: { config, ... }: is classified as module —
      # if a parametric aspect genuinely takes only { config }, wrap it in an
      # aspect envelope with explicit __functionArgs instead.
      # NixOS module functions ({ config, lib, ... }: ...) should be normalized
      # through the type system, not wrapped as parametric aspects.
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
        # Bare functions (e.g. { class, ... }: { ... }) → wrap as parametric aspect.
        else if isBareFn then
          {
            __functor = _: resolved;
            __functionArgs = bareFnArgs;
            name = "<bare-fn>";
            meta = { };
            includes = [ ];
          }
        else if needsWrap then
          {
            __functor = _: resolved.__functor resolved;
            __functionArgs = functorArgs;
            name = resolved.name or "<function body>";
            meta = resolved.meta or { };
            includes = resolved.includes or [ ];
          }
          // lib.optionalAttrs (resolved ? __scope) { inherit (resolved) __scope; }
        else
          resolved;
      # Context args (host, user) are provided by __scope handler-closures
      # on aspects, not by the root constantHandler. The root only needs
      # class and aspect-chain (added by defaultHandlers).
      ctx = { };
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
}
