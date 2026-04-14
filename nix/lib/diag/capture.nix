# Trace capture: collect structuredTrace entries from resolved aspects.
#
# Thin wrappers over the structuredTrace adapter that produce the flat
# entry lists consumed by diag.graph.build, and also the per-class
# path sets consumed by hasAspectPresent. Both come from a single
# walk — structuredTrace emits `{ trace; paths }` — so there's no
# second traversal when views need both the graph IR and the hasAspect
# query surface.
#
# Usage:
#   entries = diag.capture "nixos" rootAspect;
#   entries = diag.captureAll [ "nixos" "homeManager" ] rootAspect;
#   { entries, pathsByClass } = diag.captureWithPaths classes rootAspect;
{ den, lib }:
let
  inherit (den.lib.aspects) adapters resolve;

  # Raw result from structuredTrace for a single class.
  captureRaw = class: aspect: resolve.withAdapter adapters.structuredTrace class aspect;

  # Capture trace entries for a single class.
  capture = class: aspect: (captureRaw class aspect).trace or [ ];

  # Capture trace entries across multiple classes and concatenate.
  captureAll = classes: aspect: lib.concatMap (class: capture class aspect) classes;

  # Capture entries + per-class path sets in a single pass. The path
  # sets are attrset-as-set (keyed by slash-joined aspectPath) and
  # can be fed directly into `hasAspectPresent`.
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
