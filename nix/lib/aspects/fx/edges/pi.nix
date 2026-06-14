# pi.nix — the static Π(root) projection builder. Π is the root-pure context
# slice every delivery edge materializes against; this constructor assembles the
# STATIC subset — the 9 fields no edge step ever mutates — from already-projected
# pipeline end-state. NOT static Π and therefore NOT built here (the caller merges
# them in after): the fold accumulator { classImports; perScope } (read+written by
# edge steps) and the route/provides fold-input fields (provides; routes).
# Per-root, never global — roots differ in isolationMode / dedupMode / allScopeIds,
# so each edge materializes under its OWN root's dials.
{ lib, ... }:
{
  #   rootScopeId          — the subtree root (pipeline root | hostScopeId | spawnRoot).
  #   scopeContexts        — the context slice route/provides/synthesize materialize
  #                          against (inert for the default-fold merge).
  #   scopeParent / scopeIsolated — the parent DAG + isolation marks.
  #   isolationMode        — "aware" | "blind" (EXPLICIT, never defaulted).
  #   contextsAreAugmented — whether scopeContexts carries assemblePipes output.
  #   dedupMode            — "dedup" (default) | "raw" (spawn final extraction).
  #   allScopeIds          — optional subtree-universe override; OMITTED when null
  #                          so assembleSubtree derives it from perScope attrnames.
  #   classInject          — resolved entity class to inject (default null).
  mkStaticPi =
    {
      rootScopeId,
      scopeContexts,
      scopeParent,
      scopeIsolated,
      isolationMode,
      contextsAreAugmented ? true,
      dedupMode ? "dedup",
      allScopeIds ? null,
      classInject ? null,
    }:
    {
      inherit
        rootScopeId
        scopeContexts
        scopeParent
        scopeIsolated
        isolationMode
        contextsAreAugmented
        dedupMode
        classInject
        ;
    }
    // lib.optionalAttrs (allScopeIds != null) { inherit allScopeIds; };
}
