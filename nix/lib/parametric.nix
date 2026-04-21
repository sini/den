{ lib, den, ... }:
let
  warn = msg: v: lib.warn "den.lib.parametric: ${msg}" v;

  inherit (den.lib.aspects.fx.handlers) constantHandler;

  # fixedTo pins context values via __scopeHandlers. The fx pipeline's
  # scope.provide installs these for parametric children via bind.fn.
  parametric.fixedTo.__functor =
    _: ctx: aspect:
    warn "fixedTo is deprecated — the fx pipeline provides context via effects" (
      aspect // { __scopeHandlers = constantHandler ctx; }
    );
  parametric.fixedTo.exactly =
    ctx: aspect:
    warn "fixedTo.exactly is deprecated" (aspect // { __scopeHandlers = constantHandler ctx; });
  parametric.fixedTo.atLeast =
    ctx: aspect:
    warn "fixedTo.atLeast is deprecated" (aspect // { __scopeHandlers = constantHandler ctx; });
  parametric.fixedTo.upTo =
    ctx: aspect:
    warn "fixedTo.upTo is deprecated" (aspect // { __scopeHandlers = constantHandler ctx; });

  parametric.atLeast = aspect: warn "atLeast is deprecated — use plain attrsets" aspect;
  parametric.exactly = aspect: warn "exactly is deprecated — use plain attrsets" aspect;
  # expands merges extra context attrs into __scopeHandlers for parametric children.
  parametric.expands =
    attrs: aspect:
    let
      existing = aspect.__scopeHandlers or { };
    in
    warn "expands is deprecated" (aspect // { __scopeHandlers = existing // constantHandler attrs; });

  parametric.__functor = _: parametric.atLeast;
in
parametric
