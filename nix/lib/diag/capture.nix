# Trace capture: collect structuredTrace entries from resolved aspects.
#
# When den.fxPipeline is enabled, capture uses the fx pipeline's
# tracingHandler. Otherwise, uses legacy resolve.withAdapter.
#
# Usage:
#   entries = diag.capture "nixos" rootAspect;
#   entries = diag.captureAll [ "nixos" "homeManager" ] rootAspect;
#   { entries, pathsByClass } = diag.captureWithPaths classes rootAspect;
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
in
{
  inherit capture captureAll captureWithPaths;
}
