# instantiate-edges.nix — the per-host re-walk's surfaced edge set. The default-
# fold merge edge is a pure projection of the SAME inputs resolve.nix's
# mkInstantiateArgs derives for one host subtree (built from the SHARED
# edges/default.nix constructor, converging on what the read-only oracle consumes,
# spec §3a). The provides+routes edges are NOT re-derived: they are the CAPTURE
# from the per-host materializeUnified fold (Task 18.2), so the surfaced per-host
# set can never drift from what the fold actually dispatched.
#
# This helper builds the edge SET only; mkInstantiateArgs still returns
# { modules; pkgs?; } unchanged (that dict is forwarded into spec.instantiate, so
# it must NOT carry edges). The B′ hostConfigs pass reuses the per-host projection,
# so it reuses this too.
{ lib, den }:
let
  inherit (import ./default.nix { inherit lib; }) defaultFoldEdges;
in
{
  # The per-host re-walk's surfaced edge set (default-fold merge @ hostScopeId +
  # the CAPTURED provides+routes edges the per-host fold dispatched).
  #
  #   name             — sid → stable scope name (edge.nix scopeName); the unified
  #                      "<kind>:<id_hash>" normalization the oracle/unified set use.
  #   scopeParent      — the parent DAG slice (subtree/appendToParent walks).
  #   scopeIsolated    — the isolation-AWARE marks the per-host walk uses; governs
  #                      the default-fold subtree boundary (corollary 2 edge-absence).
  #   hostScopeId      — the host subtree root (the single entity-root + route root).
  #   subtreeScopeIds  — the host subtree's scope-id universe (defaultFoldEdges
  #                      allScopeIds — its internal subtree walk's membership set).
  #   perScope         — sid → { class → bool|content }; only `? class` membership
  #                      is read by the default fold (classContentAt).
  #   capturedEdges    — the provides+routes edges captured from the per-host
  #                      materializeUnified{exposeEdges=true}.edges fold (Task 18.2).
  mkInstantiateEdges =
    {
      name,
      scopeParent,
      scopeIsolated,
      hostScopeId,
      subtreeScopeIds,
      perScope,
      capturedEdges,
    }:
    (defaultFoldEdges {
      inherit name scopeParent scopeIsolated;
      classContentAt = perScope;
      allScopeIds = subtreeScopeIds;
      entityRootScopes = [ hostScopeId ];
    })
    ++ capturedEdges;
}
