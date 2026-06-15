# Effect handlers: register-constraint, check-constraint
# Manages the constraint registry (exclude, substitute, filter) and
# evaluates constraints against node identities during tree walk.
{
  lib,
  den,
  ...
}:
let
  lookupEntries =
    registry: nodeIdentity:
    let
      exact = registry.${nodeIdentity} or [ ];
      parts = lib.splitString "/" nodeIdentity;
      prefixes = lib.genList (i: lib.concatStringsSep "/" (lib.take (i + 1) parts)) (
        builtins.length parts - 1
      );
    in
    if registry == { } then
      exact
    else if builtins.length parts > 1 then
      exact ++ builtins.concatMap (p: registry.${p} or [ ]) prefixes
    else
      exact;

  # Chain-prefix ancestry: is `ownerChain` a prefix of the includes `chain`. The
  # shared scope-relevance atom (also consumed by compile-conditional.nix).
  isAncestorChain = chain: ownerChain: lib.take (builtins.length ownerChain) chain == ownerChain;

  filterByScope =
    currentChain: entries:
    let
      inScope =
        entry:
        (entry.scope or "global") == "global" || isAncestorChain currentChain (entry.ownerChain or [ ]);
    in
    builtins.filter inScope entries;

  # Merge the scoped constraint registry over `scope` + its ancestors into one
  # identity→entries map. Entity isolation (#613 analog for the exclude/substitute
  # APPLICATION path): a SIBLING entity's excludes live under the sibling's scope
  # key and are therefore ABSENT here — so one host excluding an aspect can no
  # longer suppress a sibling host that includes it (the leak was eval-order
  # dependent: a sibling walked earlier registered into the fleet-wide flat
  # registry). ownerChain is PRESERVED (unlike the guard path's
  # collectScopeConstraints, which normalizes it) so filterByScope still isolates
  # nested includes WITHIN the scope. Own-scope entries precede ancestor entries
  # (first-wins precedence).
  collectEntityConstraints =
    scopedRegistry: scopeParentMap: scope:
    let
      # Cycle-guarded (visited set): scopeParent can carry a cycle in spawn/forward
      # merged sub-pipelines, and check-constraint runs for EVERY node — so the walk
      # must stop on any revisit, not just a self-loop.
      go =
        seen: s: acc:
        if s == null || seen ? ${s} then
          acc
        else
          let
            merged = lib.zipAttrsWith (_: builtins.concatLists) [
              acc
              (scopedRegistry.${s} or { })
            ];
            parent = scopeParentMap.${s} or null;
          in
          go (seen // { ${s} = true; }) parent merged;
    in
    if scope == null then { } else go { } scope { };

  entryToResume =
    entry:
    if entry.type == "exclude" then
      {
        action = "exclude";
        inherit (entry) owner;
      }
    else if entry.type == "substitute" then
      {
        action = "substitute";
        replacement = entry.getReplacement null;
        inherit (entry) owner;
      }
    else
      { action = "keep"; };

  constraintRegistryHandler = {
    "register-constraint" =
      { param, state }:
      let
        inherit (state) currentScope;
        ownerChain = ((state.scopedIncludesChain or (_: { })) null).${currentScope} or [ ];
        scope = param.scope or "subtree";
      in
      if param.type == "filter" then
        let
          filterEntry = {
            inherit (param) predicate;
            owner = param.owner or "<anon>";
            inherit scope ownerChain;
          };
        in
        {
          resume = null;
          state = state // {
            flatConstraintFilters = (state.flatConstraintFilters or [ ]) ++ [ filterEntry ];
          };
        }
      else
        let
          entry = {
            inherit (param) type;
            getReplacement = param.getReplacement or (_: null);
            owner = param.owner or "<anon>";
            inherit scope ownerChain;
          };
          flatReg = state.flatConstraintRegistry or { };
          existing = flatReg.${param.identity} or [ ];
        in
        {
          resume = null;
          state =
            let
              all = (state.scopedConstraintRegistry or (_: { })) null;
              inherit (state) currentScope;
              scopeData = all.${currentScope} or { };
              updatedRegistry = all // {
                ${currentScope} = scopeData // {
                  ${param.identity} = (scopeData.${param.identity} or [ ]) ++ [ entry ];
                };
              };
            in
            (state // { scopedConstraintRegistry = _: updatedRegistry; })
            // {
              flatConstraintRegistry = flatReg // {
                ${param.identity} = existing ++ [ entry ];
              };
            };
        };

    "check-constraint" =
      { param, state }:
      let
        nodeIdentity = if builtins.isAttrs param then param.identity else param;
        aspect = if builtins.isAttrs param then param.aspect or null else null;
        currentChain = ((state.scopedIncludesChain or (_: { })) null).${state.currentScope} or [ ];
        # #613 analog: look excludes/substitutes up in the ENTITY-scoped registry
        # (currentScope + ancestors), NOT the fleet-wide flat registry — a sibling
        # host's exclude must not suppress this node (the leak was eval-order
        # dependent). filterByScope still applies for within-scope include nesting.
        scopedRegistry = (state.scopedConstraintRegistry or (_: { })) null;
        scopeParentMap = (state.scopeParent or (_: { })) null;
        entityRegistry = collectEntityConstraints scopedRegistry scopeParentMap state.currentScope;
        allEntries = lookupEntries entityRegistry nodeIdentity;
        scopedEntries = filterByScope currentChain allEntries;
        firstEntry = if scopedEntries == [ ] then null else builtins.head scopedEntries;
      in
      if firstEntry != null then
        {
          resume = entryToResume firstEntry;
          inherit state;
        }
      else
        let
          scopedFilters = filterByScope currentChain (state.flatConstraintFilters or [ ]);
          failedFilter =
            if aspect != null then lib.findFirst (f: !(f.predicate aspect)) null scopedFilters else null;
        in
        if failedFilter != null then
          {
            resume = {
              action = "exclude";
              inherit (failedFilter) owner;
            };
            inherit state;
          }
        else
          {
            resume = {
              action = "keep";
            };
            inherit state;
          };
  };
in
{
  inherit constraintRegistryHandler lookupEntries isAncestorChain;
}
