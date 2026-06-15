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

  # Cycle-guarded fold up the scopeParent chain from `scope`, merging each scope's
  # value (`at s`) into the accumulator via `merge`. The shared scope+ancestor walk
  # skeleton (constraint registry AND the guard pathSet, compile-conditional.nix).
  # Stops on null or any revisit — scopeParent can cycle in spawn/forward merged
  # sub-pipelines. Own/closer scopes are merged before ancestors.
  foldScopeAncestors =
    merge: scopeParentMap: at: scope:
    let
      go =
        seen: s: acc:
        if s == null || seen ? ${s} then
          acc
        else
          go (seen // { ${s} = true; }) (scopeParentMap.${s} or null) (merge acc (at s));
    in
    go { } scope { };

  # The constraint registry relevant to a scope, as one identity→entries map —
  # the merge of the scope's own + ANCESTOR scopes' entries (cycle-guarded walk
  # up scopeParent). Replaces the fleet-wide flat registry: it is the SINGLE
  # lookup all readers share (check-constraint + the policy-name exclusion
  # filters), so the flat registry is gone. A SIBLING entity's excludes live under
  # the sibling's scope key — NOT an ancestor — and are therefore ABSENT, fixing
  # the eval-order sibling-leak (#613 analog) for BOTH aspect-content excludes
  # (`den.aspects.X.excludes`) and policy-name excludes. Schema-tier excludes
  # (`den.schema.KIND.excludes`) register at the resolved KIND scope and reach
  # descendants via the ancestor walk (the late-policy dispatch scopes to the
  # SIBLING it emits for — see scopedConstraintsForScope — so a kind's own
  # excludes are in scope). Cycle-guarded: scopeParent can cycle in spawn/forward
  # merged sub-pipelines, and check-constraint runs for EVERY node.
  collectScopedConstraints =
    scopedRegistry: scopeParentMap: scope:
    foldScopeAncestors (
      a: b:
      lib.zipAttrsWith (_: builtins.concatLists) [
        a
        b
      ]
    ) scopeParentMap (s: scopedRegistry.${s} or { }) scope;

  # The shared entry point: build the scope-relevant constraint registry from
  # pipeline state, FOR a given target scope. Every reader goes through this, so
  # there is ONE registry (no fleet-wide flat duplicate). The scope is explicit
  # because the LATE-policy dispatch (policy/schema emitLateForSibling) runs at the
  # PARENT scope but emits for a CHILD sibling — it must scope to the sibling
  # (where that sibling's + its kind's excludes live), not the parent. `scope ==
  # null` (bare-handler unit tests / empty state) ⇒ empty registry.
  scopedConstraintsForScope =
    state: scope:
    collectScopedConstraints ((state.scopedConstraintRegistry or (_: { })) null) (
      (state.scopeParent or (_: { }))
      null
    ) scope;

  # The common case: scope to the state's currentScope.
  scopedConstraintsFor = state: scopedConstraintsForScope state (state.currentScope or null);

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
        in
        {
          resume = null;
          # Only the scope-keyed registry is written; all readers go through
          # scopedConstraintsFor (entity-scoped: scope + ancestors), so the former
          # fleet-wide flatConstraintRegistry — which leaked excludes across
          # siblings — is gone.
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
            state // { scopedConstraintRegistry = _: updatedRegistry; };
        };

    "check-constraint" =
      { param, state }:
      let
        nodeIdentity = if builtins.isAttrs param then param.identity else param;
        aspect = if builtins.isAttrs param then param.aspect or null else null;
        currentChain = ((state.scopedIncludesChain or (_: { })) null).${state.currentScope} or [ ];
        # #613 analog: entity-scoped registry (scopedConstraintsFor: scope +
        # ancestors), NOT the fleet-wide flat registry — a sibling entity's exclude
        # must not suppress this node. filterByScope still applies for within-scope
        # include nesting.
        allEntries = lookupEntries (scopedConstraintsFor state) nodeIdentity;
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
  inherit
    constraintRegistryHandler
    lookupEntries
    isAncestorChain
    foldScopeAncestors
    collectScopedConstraints
    scopedConstraintsFor
    scopedConstraintsForScope
    ;
}
