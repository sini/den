# Trace capture: collect structuredTrace entries from resolved aspects.
#
# When den.fxPipeline is enabled, capture uses the fx pipeline's
# tracingHandler. Otherwise, uses legacy resolve.withAdapter.
#
# Usage:
#   entries = diag.capture "nixos" rootAspect;
#   entries = diag.captureAll [ "nixos" "homeManager" ] rootAspect;
#   { entries, pathsByClass } = diag.captureWithPaths classes rootAspect;
#   { entries, pathsByClass, ctxTrace } = diag.fxCaptureWithPaths fxLib classes rootAspect;
{
  den,
  lib,
  inputs ? { },
  ...
}:
let
  inherit (den.lib.aspects) adapters;
  legacyResolve = den.lib.aspects.legacyResolve or den.lib.aspects.resolve;

  # Legacy capture path.
  captureRaw = class: aspect: legacyResolve.withAdapter adapters.structuredTrace class aspect;

  capture = class: aspect: (captureRaw class aspect).trace or [ ];

  captureAll = classes: aspect: lib.concatMap (class: capture class aspect) classes;

  captureWithPaths =
    classes: aspect:
    let
      raw = lib.genAttrs classes (c: captureRaw c aspect);
    in
    {
      entries = lib.concatMap (c: (raw.${c}).trace or [ ]) classes;
      pathsByClass = lib.mapAttrs (_: r: adapters.toPathSet (r.paths or [ ])) raw;
    };

  # FX-native capture: resolve pre-built root with trace handlers.
  # Returns { entries, pathsByClass, ctxTrace } so callers don't need
  # to pull ctxTrace from a separate source.
  #
  # fxCaptureWithPathsWith accepts extraHandlers to compose additional
  # handlers (timing, debug, etc.) into the pipeline.
  fxCaptureWithPathsWith =
    {
      fxLib,
      classes,
      root,
      extraHandlers ? { },
    }:
    let
      nxFx = inputs.nix-effects.lib;
      rawPerClass = lib.genAttrs classes (
        class:
        let
          comp = fxLib.aspect.aspectToEffect root;
        in
        nxFx.handle {
          handlers = fxLib.pipeline.composeHandlers (fxLib.pipeline.defaultHandlers {
            inherit class;
            ctx = { };
          }) (fxLib.trace.tracingHandler class // extraHandlers);
          state = fxLib.pipeline.defaultState // {
            entries = [ ];
            paths = [ ];
            ctxTrace = [ ];
          };
        } comp
      );
    in
    {
      entries = lib.concatMap (c: (rawPerClass.${c}).state.entries) classes;
      pathsByClass = lib.mapAttrs (_: r: fxLib.identity.toPathSet (r.state.paths or [ ])) rawPerClass;
      ctxTrace =
        let
          first = rawPerClass.${lib.head classes};
        in
        first.state.ctxTrace or [ ];
    };

  # Simple 3-arg wrapper; backward-compatible with existing callers.
  fxCaptureWithPaths =
    fxLib: classes: root:
    fxCaptureWithPathsWith { inherit fxLib classes root; };
in
{
  inherit
    capture
    captureAll
    captureWithPaths
    fxCaptureWithPaths
    fxCaptureWithPathsWith
    ;
}
