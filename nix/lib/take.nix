# Deprecated context-level guards.
# Under handler-based resolution, bind.fn resolves args from handlers.
# take.exactly uses optional-arg detection to gate on context level.
# take.atLeast and take.upTo are identity (the pipeline's deferral
# provides atLeast semantics naturally).
{ den, lib, ... }:
let
  allContextKeys = [
    "host"
    "user"
    "home"
  ];

  take.unused = _unused: used: used;

  take.exactly =
    fn:
    let
      args = lib.functionArgs fn;
      requiredKeys = builtins.filter (k: !args.${k}) (builtins.attrNames args);
      extraKeys = builtins.filter (k: !(builtins.elem k requiredKeys)) allContextKeys;
      funcArgs = lib.genAttrs requiredKeys (_: false) // lib.genAttrs extraKeys (_: true);
    in
    if requiredKeys == [ ] then
      fn
    else
      lib.warn "den.lib.take.exactly is deprecated — bind.fn resolves args from handlers" {
        __functor =
          self: resolvedArgs:
          let
            hasExtras = builtins.any (k: resolvedArgs ? ${k}) extraKeys;
          in
          if hasExtras then { } else fn (lib.intersectAttrs (lib.genAttrs requiredKeys (_: null)) resolvedArgs);
        __functionArgs = funcArgs;
        includes = [ ];
      };

  take.atLeast =
    fn:
    lib.warn "den.lib.take.atLeast is deprecated — bind.fn resolves args from handlers" fn;

  take.upTo =
    fn:
    lib.warn "den.lib.take.upTo is deprecated — bind.fn resolves args from handlers" fn;

  # Deprecated: custom predicate form.
  take.__functor =
    _: _canTakePred: _argAdapter: fn:
    lib.warn "den.lib.take custom predicate is deprecated — use plain parametric functions" fn;
in
take
