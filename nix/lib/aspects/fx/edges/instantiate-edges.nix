# instantiate-edges.nix — the per-host re-walk's surfaced edge set. A pure
# projection of the SAME inputs resolve.nix's mkInstantiateArgs already derives
# for one host subtree (default-fold merge @ hostScopeId + provides over
# subtreeProvides + routes over subtreeRoutes). It is built from the SHARED
# constructors (edges/default.nix, edges/provides.nix, edges/route.nix) so the
# surfaced per-host set converges on the constructors the read-only oracle
# (edge-trace.nix) consumes (spec §3a convergence), exactly as the spawn re-entry
# (edges/materialize.nix assembleSpawnSubtree) surfaces its own edge set.
#
# This helper builds the edge SET only; mkInstantiateArgs still returns
# { modules; pkgs?; } unchanged (that dict is forwarded into spec.instantiate, so
# it must NOT carry edges). A later task (16.3) collects this output — the B′
# hostConfigs pass reuses mkInstantiateArgs per peer host, so it reuses this too.
{ lib, den }:
let
  inherit (import ./default.nix { inherit lib; }) defaultFoldEdges;
  inherit (import ./provides.nix { inherit lib den; }) providesEdges;
  inherit (import ./route.nix { inherit lib den; }) routeEdges;
in
{
  # The per-host re-walk's surfaced edge set (default-fold merge @ hostScopeId +
  # provides over subtreeProvides + routes over subtreeRoutes). Pure projection of
  # the inputs mkInstantiateArgs already derives — see resolve.nix mkInstantiateArgs.
  #
  #   name             — sid → stable scope name (edge.nix scopeName); the unified
  #                      "<kind>:<id_hash>" normalization the oracle/unified set use.
  #   scopeParent      — the parent DAG slice (subtree/appendToParent walks).
  #   scopeIsolated    — the isolation-AWARE marks the per-host walk uses; governs
  #                      the default-fold subtree boundary (corollary 2 edge-absence).
  #   hostScopeId      — the host subtree root (the single entity-root + route root).
  #   subtreeProvides  — sid → [ provide specs ] over the host subtree.
  #   subtreeRoutes    — sid → [ route specs ] over the host subtree.
  #   subtreeScopeIds  — the host subtree's scope-id universe (defaultFoldEdges
  #                      allScopeIds — its internal subtree walk's membership set).
  #   perScope         — sid → { class → bool|content }; only `? class` membership
  #                      is read by the default fold (classContentAt).
  mkInstantiateEdges =
    {
      name,
      scopeParent,
      scopeIsolated,
      hostScopeId,
      subtreeProvides,
      subtreeRoutes,
      subtreeScopeIds,
      perScope,
    }:
    (defaultFoldEdges {
      inherit name scopeParent scopeIsolated;
      classContentAt = perScope;
      allScopeIds = subtreeScopeIds;
      entityRootScopes = [ hostScopeId ];
    })
    ++ (providesEdges {
      inherit name;
      scopedProvides = subtreeProvides;
    })
    ++ (routeEdges {
      inherit name scopeParent;
      rootScopeId = hostScopeId;
      rawRoutes = lib.concatLists (lib.attrValues subtreeRoutes);
    });
}
