# default.nix — edge constructors. The constructor functions that turn recorded
# pipeline state into delivery edges (spec §3c "edge collection"). Both the
# read-only oracle (edge-trace.nix) and the production materializer
# (materialize.nix → resolve.nix) source their edges from HERE, so extractor and
# production can never disagree on an edge's shape (spec §3a convergence).
#
# This file holds the DEFAULT-FOLD constructor. The other mechanisms' edge
# constructors live in their own siblings: routes + complex forwards in route.nix,
# provides in provides.nix, the flake-output T-arm in instantiate.nix. The spawn
# now SURFACES real delivery edges via these shared constructors (its default fold
# + the captured provides/routes of its materializeUnified fold, see
# edges/materialize.nix assembleSpawnSubtree.edges) — they enter the production
# `edgeTrace`. The legacy `rewalk`-edge render (edge-trace.nix spawnEdges) is now
# ONLY the legacy-differential arm, not the live trace.
{ lib, ... }:
let
  inherit (import ./edge.nix { inherit lib; }) mkEdge collected rootTarget;
  inherit (import ../scope-walk.nix { inherit lib; }) subtreeScopes;
in
{
  # ===== default fold edges =============================================
  # Corollary 1 (spec §2): every entity-root scope contributes one merge edge
  # per class with content —
  #   collected(subtree minus isolated, class) → (root, class), P=[], M=merge.
  # `isolated` is consumed HERE, at edge construction (the subtree boundary via
  # subtreeScopes), NOT inside the materializer — corollary 2: isolation is
  # edge-absence, never a mid-walk filter. An isolated descendant is its OWN
  # entity-root, so it is ABSENT from its parent's collected subtree and emits
  # its own fold edge instead.
  #
  # The edge records the source as the subtree's ROOT scope name + class (spec
  # §8 records the collected(scope,class) IDENTITY, not enumerated content). The
  # collectedScopes annotation surfaces the isolation-aware subtree membership so
  # the isolation-as-edge-absence corollary can assert with teeth (an isolated
  # child's scope name must NOT appear in its parent fold's collectedScopes).
  #
  # Inputs are already-projected pipeline end-state:
  #   name            — sid → stable scope name (edge.nix scopeName, bound to the
  #                     pipeline's scopeEntityKind+scopeContexts).
  #   scopeParent     — the parent DAG (for the subtree walk).
  #   scopeIsolated   — { sid → bool } isolation marks (subtree boundary).
  #   classContentAt  — sid → { class → bool|content } presence map (any scope's
  #                     class buckets); only `? class` membership is read.
  #   allScopeIds     — every scope id in the projection.
  #   entityRootScopes — the roots to emit folds for (pipeline root + isolated
  #                     scopes, each its own root per corollary 2).
  defaultFoldEdges =
    {
      name,
      scopeParent,
      scopeIsolated,
      classContentAt,
      allScopeIds,
      entityRootScopes,
    }:
    builtins.concatLists (
      map (
        rootSid:
        let
          subtree = subtreeScopes {
            inherit scopeParent allScopeIds;
            isolated = scopeIsolated;
            root = rootSid;
          };
          # Classes with any content anywhere in the isolation-aware subtree.
          classesWithContent = lib.unique (
            builtins.concatLists (map (sid: builtins.attrNames (classContentAt.${sid} or { })) subtree)
          );
          hasContent = cls: builtins.any (sid: (classContentAt.${sid} or { }) ? ${cls}) subtree;
          # Normalized names of every scope this fold collects from. An isolated
          # descendant is its OWN root, so it is ABSENT here (corollary 2).
          collectedScopes = lib.sort (a: b: a < b) (lib.unique (map name subtree));
        in
        map (
          cls:
          mkEdge {
            source = collected (name rootSid) cls;
            target = rootTarget (name rootSid) cls;
            path = [ ];
            mode = "merge";
            annotations = {
              inherit collectedScopes;
            };
          }
        ) (builtins.filter hasContent classesWithContent)
      ) entityRootScopes
    );
}
