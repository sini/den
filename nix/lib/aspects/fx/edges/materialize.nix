# materialize.nix — the edge materializer (spec §3c "materialization"). Given a
# context projection Π and the edges targeting a root, produce the root's
# per-class content. This is the single mechanism that replaces the phase-fold
# re-entries' final extraction; phase ordering becomes edge toposort (corollary
# 5) as later mechanisms are ported.
#
# Tasks 7–8 are complete: `merge` (default-fold port) and `nest`/`nest-verbatim`
# (route delivery via materializeRouteEdge) are both live. The else-throw in the
# `materialize` switch below is NOT a Task 8 stub — it is permanently correct:
# `assembleSubtree` carries merge edges only; route nest/nest-verbatim delivery
# folds through route/apply.nix:applySimpleRoute → materializeRouteEdge.
#
# DESIGN INVARIANTS (spec §2 corollaries; enforced by the entity-isolation suite
# and the delivery-edges fixtures):
#   - `materialize` contains the ONLY mode switch (merge | nest | nest-verbatim).
#   - It carries NO mechanism vocabulary (no route/provides/spawn/instantiate
#     names): mechanisms are dissolved into edges before they reach here.
#   - It performs NO isolation-flag reads: isolation is consumed at edge
#     CONSTRUCTION (corollary 2 — isolation is edge-absence). `assembleSubtree`
#     resolves the subtree boundary (via scope-walk.subtreeScopes, governed by
#     Π's EXPLICIT isolationMode) BEFORE handing merge edges to the switch, so
#     the switch only walks an already-bounded scope list.
{ lib, ... }:
let
  inherit (import ../scope-walk.nix { inherit lib; }) subtreeScopes dedupByKey;
  inherit (import ./default.nix { inherit lib; }) defaultFoldEdges;
  inherit (import ./route.nix { inherit lib; }) materializeNest mkAdapterFunctor;
in
rec {
  # The Π(root) record shape (§A, Task 1 census). Per-field provenance cites the
  # census verdict that constrains it; fields not yet consumed by THIS task's
  # default-fold port still belong in the record because Tasks 8–11 consume them
  # (the variants become visible data instead of implicit state-threading).
  #
  # Π(root) = {
  #   scopeContexts;          # §9 subtree-only context slice. NOT consumed by the
  #                           #   default-fold merge (which reads perScope buckets
  #                           #   directly); routes/provides/synthesize materialize
  #                           #   against it (Tasks 8–9).
  #   contextsAreAugmented;   # §8 DELIBERATE (cycle-forced) — B′ gets raw contexts.
  #                           #   Carried so a unified assembleSubtree knows which it
  #                           #   got. Not consumed this task.
  #   classImports;           # §2 the collected class buckets, per-scope (perScope).
  #                           #   The default-fold merge SOURCE. TARGET semantics =
  #                           #   drained (Task 11 owns the B′ baseDrain ACCIDENT);
  #                           #   the Π builder must NOT enshrine raw as B′'s contract.
  #   provides;               # §9 subtree+ancestors; §3 spawn's own suffices.
  #                           #   Not consumed this task (provides port = Task 9).
  #   routes;                 # §9 subtree+ancestors; §4 parent-subtree routes merge
  #                           #   into a spawn. Not consumed this task (route = Task 8).
  #   rootScopeId;            # §5 DELIBERATE — the subtree root (pipeline root |
  #                           #   hostScopeId | spawnRoot). The merge target's root.
  #   scopeParent;            # the parent DAG slice (subtree/ancestor walks).
  #   scopeIsolated;          # §6/§10 — the isolation marks. Consulted at EXTRACTION
  #                           #   via subtreeScopes, governed by isolationMode; never
  #                           #   read inside the mode switch.
  #   isolationMode;          # §6 `aware` (default) | `blind` (spawn final extraction
  #                           #   invariant). EXPLICIT — never defaulted.
  #   classInject ? null;     # §1 the resolved entity class to inject into context
  #                           #   args; no observable witness — defensive projection,
  #                           #   default off. Not consumed this task.
  # }

  # Resolve Π's isolation marks into the `isolated` set the subtree walk takes,
  # governed by the EXPLICIT isolationMode (§A: "pass it EXPLICITLY, never by
  # defaulting"). blind ⇒ {} (the spawn final-extraction invariant); aware ⇒ the
  # scope isolation marks. This is the ONLY place an isolation mark is consulted,
  # and it happens at CONSTRUCTION (assembleSubtree), not inside the switch.
  isolatedSetOf =
    pi:
    if pi.isolationMode == "blind" then
      { }
    else if pi.isolationMode == "aware" then
      pi.scopeIsolated
    else
      throw "den materialize: isolationMode must be \"aware\" | \"blind\", got ${builtins.toJSON pi.isolationMode}";

  # Collect the merge source for a (root, class) target: the class bucket of the
  # already-bounded subtree, key-deduped first-occurrence-wins. This is exactly
  # the wrapPerScope cross-scope dedup + extractSubtreeModules semantics
  # (resolve.nix), now expressed as the merge-mode materialization rule.
  #   perScope        — sid → { class → [ modules ] } (the wrapped buckets).
  #   subtreeScopeIds — the resolved, isolation-bounded scope list.
  collectMerge =
    perScope: subtreeScopeIds: cls:
    let
      raw = lib.concatMap (sid: perScope.${sid}.${cls} or [ ]) subtreeScopeIds;
    in
    dedupByKey (m: m.key or null) raw;

  # materializeRouteEdge: the §B nest/nest-verbatim/merge placement for ONE
  # simple-route edge carrying its already-resolved source modules + materializer
  # properties → the wrapped module list to land in the target bucket. This is
  # the ONLY mode switch for route delivery; the route fold (route/apply.nix)
  # routes EVERY simple route through here so nest/nest-verbatim/merge placement
  # is decided in one place (spec §3c materialization).
  #
  # The edge carries a `materialize` payload:
  #   { modules; path; mode; adaptArgs; guard; reinstantiate; ensureTargetPath;
  #     adapterKey; adapterRoute; sourceModules; instantiateEvaluated; }
  # `adapterKey`/`instantiate` arms replace the module list outright (cells 6/7);
  # the remaining cells (1–5) go through materializeNest (nest | nest-verbatim |
  # merge contribution at P=[], + the #572 combine + ensureTargetPath).
  materializeRouteEdge =
    m:
    if m.kind == "instantiate" then
      # cell 7: eager instantiate evaluated at materialization, placed at P.
      if m.sourceModules == [ ] then
        [ ]
      else
        [ { config = lib.setAttrByPath m.path m.instantiateEvaluated; } ]
    else if m.kind == "ensure-empty" then
      # cell 5 with empty source and ensureTargetPath: land an empty attrset at P.
      lib.optional m.ensureTargetPath { config = lib.setAttrByPath m.path { }; }
    else if m.kind == "adapter" then
      # cell 6: the adapter functor module (dynamic P resolved at evalModules).
      [ (mkAdapterFunctor m.adapterRoute m.sourceModules) ]
    else
      # cells 1–4: nest | nest-verbatim | merge contribution (P=[]), + #572.
      materializeNest {
        inherit (m)
          modules
          path
          guard
          adaptArgs
          reinstantiate
          ensureTargetPath
          ;
      };

  # materialize: Π + an edge list → { class → [ modules ] }. The ONLY mode
  # switch for default-fold extraction. Routes/provides/spawn fold through their
  # own entry (route/apply.nix → materializeRouteEdge) until their phase folds are
  # absorbed (Tasks 9–11); the merge arm here is the per-root final extraction.
  # `perScope` and the resolved subtree are passed via the closure `ctx`.
  materialize =
    pi: ctx: edges:
    let
      step =
        acc: edge:
        let
          cls = edge.target.class;
        in
        if edge.mode == "merge" then
          # merge: key-deduped module-list union of the bounded subtree's bucket.
          acc
          // {
            ${cls} = (acc.${cls} or [ ]) ++ collectMerge ctx.perScope ctx.subtreeScopeIds cls;
          }
        else
          throw "den materialize: assembleSubtree edge mode ${builtins.toJSON edge.mode} (nest/nest-verbatim route delivery folds through route/apply.nix:materializeRouteEdge, not assembleSubtree, until Tasks 9–11)";
    in
    builtins.foldl' step { } edges;

  # assembleSubtree: materialize all edges targeting `root`. For the default-fold
  # port this is the per-root final extraction that replaces extractSubtreeModules
  # — the merge-mode materialization of the root's own default-fold edges.
  #
  # The subtree boundary (isolation) is resolved HERE (construction time,
  # corollary 2), producing the bounded scope list the merge switch walks. The
  # mode switch never sees an isolation flag.
  #
  #   root  — the root scope id whose content is being assembled.
  #   pi    — the Π(root) projection (shape above).
  # Returns { class → [ modules ] }; a class with no content is absent (callers
  # treat absence as null, matching extractSubtreeModules' `== [] then null`).
  assembleSubtree =
    { root, pi }:
    let
      allScopeIds = builtins.attrNames pi.perScope;
      # The isolation set the subtree boundary uses, governed by pi.isolationMode.
      # Computed ONCE here so the merge-collection walk and the edge constructor's
      # own internal subtree walk agree on the boundary.
      isolated = isolatedSetOf pi;
      subtreeScopeIds = subtreeScopes {
        inherit (pi) scopeParent;
        inherit isolated root allScopeIds;
      };
      # Default-fold edges for THIS root, built by the SHARED constructor
      # (edges/default.nix defaultFoldEdges) — the same function the read-only
      # oracle (edge-trace.nix) consumes, so production and oracle agree on the
      # CONSTRUCTOR, not merely the primitives (spec §3a convergence).
      # Adaptation to assembleSubtree's per-root, isolationMode-governed call:
      #   - entityRootScopes = [ root ] (this single root; isolated descendants
      #     are their own roots, materialized by their own assembleSubtree).
      #   - scopeIsolated = `isolated` (already resolved through isolationMode, so
      #     the constructor's internal subtree walk matches subtreeScopeIds).
      #   - classContentAt = pi.perScope (only `? class` membership is read).
      #   - name = identity: the merge switch reads ONLY edge.target.class, so the
      #     T.root naming used by the oracle is irrelevant here; identity keeps the
      #     emitted target.root = the raw sid, unchanged from the prior inline form.
      edges = defaultFoldEdges {
        name = sid: sid;
        inherit (pi) scopeParent;
        scopeIsolated = isolated;
        classContentAt = pi.perScope;
        inherit allScopeIds;
        entityRootScopes = [ root ];
      };
    in
    materialize pi {
      inherit (pi) perScope;
      inherit subtreeScopeIds;
    } edges;
}
