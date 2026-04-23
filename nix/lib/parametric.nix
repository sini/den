{ lib, den, ... }:
let
  warn = msg: v: lib.warn "den.lib.parametric: ${msg}" v;

  # fixedTo pins context values via __ctx tagging. The fx pipeline's
  # constantHandler resolves these for parametric children via bind.fn.
  parametric.fixedTo.__functor =
    _: ctx: aspect:
    warn "fixedTo is deprecated — the fx pipeline provides context via effects" (
      aspect // { __ctx = ctx; }
    );
  parametric.fixedTo.exactly =
    ctx: aspect: warn "fixedTo.exactly is deprecated" (aspect // { __ctx = ctx; });
  parametric.fixedTo.atLeast =
    ctx: aspect: warn "fixedTo.atLeast is deprecated" (aspect // { __ctx = ctx; });
  parametric.fixedTo.upTo =
    ctx: aspect: warn "fixedTo.upTo is deprecated" (aspect // { __ctx = ctx; });

  parametric.atLeast = aspect: warn "atLeast is deprecated — use plain attrsets" aspect;
  parametric.exactly = aspect: warn "exactly is deprecated — use plain attrsets" aspect;
  # expands merges extra context attrs into __ctx for parametric children.
  parametric.expands = attrs: aspect: warn "expands is deprecated" (aspect // { __ctx = attrs; });

  parametric.__functor = _: parametric.atLeast;
in
parametric
