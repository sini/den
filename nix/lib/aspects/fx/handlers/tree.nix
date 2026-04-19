# constraintRegistryHandler: Handles register-constraint, check-constraint
#   State reads: constraintRegistry, constraintFilters, includesChain
#   State writes: constraintRegistry, constraintFilters
# chainHandler: Handles chain-push, chain-pop
#   State reads/writes: includesChain
# classCollectorHandler: Handles emit-class
#   State reads/writes: imports
{
  lib,
  den,
  ...
}:
let
  # Constraint registry. Handles register-constraint and check-constraint effects.
  # Supports identity-based (exclude, substitute) and predicate-based (filter).
  constraintRegistryHandler = {
    "register-constraint" =
      { param, state }:
      let
        ownerChain = state.includesChain or [ ];
        scope = param.scope or "subtree";
      in
      if param.type == "filter" then
        {
          resume = null;
          state = state // {
            constraintFilters = (state.constraintFilters or [ ]) ++ [
              {
                predicate = param.predicate;
                owner = param.owner or "<anon>";
                inherit scope ownerChain;
              }
            ];
          };
        }
      else
        let
          existing = (state.constraintRegistry or { }).${param.identity} or [ ];
          entry = {
            type = param.type;
            getReplacement = param.getReplacement or (_: null);
            owner = param.owner or "<anon>";
            inherit scope ownerChain;
          };
        in
        {
          resume = null;
          state = state // {
            constraintRegistry = (state.constraintRegistry or { }) // {
              ${param.identity} = existing ++ [ entry ];
            };
          };
        };

    # Check if an aspect should be excluded/substituted/filtered.
    # First checks identity-based registry, then predicate filters.
    # param = { identity; aspect; } or a bare identity string (used by tests).
    "check-constraint" =
      { param, state }:
      let
        identity = if builtins.isAttrs param then param.identity else param;
        aspect = if builtins.isAttrs param then param.aspect or null else null;
        registry = state.constraintRegistry or { };
        filters = state.constraintFilters or [ ];
        currentChain = state.includesChain or [ ];
        # True when ownerChain is a prefix of currentChain (subtree membership).
        isAncestor = ownerChain: lib.take (builtins.length ownerChain) currentChain == ownerChain;
        inScope = entry: (entry.scope or "global") == "global" || isAncestor (entry.ownerChain or [ ]);
        mkDecision = action: extra: {
          resume = {
            inherit action;
          }
          // extra;
          inherit state;
        };
        # Find first in-scope constraint for this identity (first-registered wins).
        # Also check prefix matches: excluding "monitoring" cascades to "monitoring/node-exporter".
        entries = registry.${identity} or [ ];
        prefixEntries =
          let
            parts = lib.splitString "/" identity;
            # Generate all proper prefixes: for "a/b/c" → ["a", "a/b"]
            prefixes = lib.genList (i: lib.concatStringsSep "/" (lib.take (i + 1) parts)) (
              builtins.length parts - 1
            );
            getEntries = p: registry.${p} or [ ];
          in
          if builtins.length parts > 1 then builtins.concatMap getEntries prefixes else [ ];
        allEntries = entries ++ prefixEntries;
        scopedEntries = builtins.filter inScope allEntries;
        firstEntry = if scopedEntries == [ ] then null else builtins.head scopedEntries;
      in
      if firstEntry != null then
        if firstEntry.type == "exclude" then
          mkDecision "exclude" { owner = firstEntry.owner; }
        else if firstEntry.type == "substitute" then
          mkDecision "substitute" {
            replacement = firstEntry.getReplacement null;
            owner = firstEntry.owner;
          }
        else
          mkDecision "keep" { }
      else
        # No in-scope identity match — check predicate filters.
        let
          scopedFilters = builtins.filter inScope filters;
          failedFilter =
            if aspect != null then lib.findFirst (f: !(f.predicate aspect)) null scopedFilters else null;
        in
        if failedFilter != null then
          mkDecision "exclude" { owner = failedFilter.owner; }
        else
          mkDecision "keep" { };
  };

  # Maintains includes-path stack. chain-push appends identity, chain-pop removes last.
  chainHandler = {
    "chain-push" =
      { param, state }:
      {
        resume = null;
        state = state // {
          includesChain = (state.includesChain or [ ]) ++ [ param.identity ];
        };
      };
    "chain-pop" =
      { param, state }:
      let
        chain = state.includesChain or [ ];
      in
      {
        resume = null;
        state = state // {
          includesChain =
            if chain == [ ] then
              throw "fx: chain-pop on empty includesChain — push/pop mismatch in aspect compiler"
            else
              lib.init chain;
        };
      };
  };

  # Accumulates class modules from emit-class effects.
  # Only collects modules for the specified target class.
  classCollectorHandler =
    {
      targetClass,
    }:
    {
      "emit-class" =
        { param, state }:
        let
          _t = builtins.trace "classCollector: class=${param.class} target=${targetClass} identity=${param.identity or "?"} match=${
            toString (param.class == targetClass)
          }";
        in
        _t (
          if param.class != targetClass then
            {
              resume = null;
              inherit state;
            }
          else
            let
              identity = param.identity or "<anon>";
              loc = "${param.class}@${identity}";
              # Named aspects get a key for NixOS module-level dedup: two
              # resolve calls emitting the same aspect:class produce the
              # same key, so the module system keeps only the first.
              # Anonymous/synthetic names must not be keyed — multiple
              # anonymous includes with the same identity are distinct.
              isAnon =
                identity == "<anon>"
                || identity == "<function body>"
                || lib.hasPrefix "[definition " identity
                || lib.hasPrefix "<root>/" identity
                || lib.hasInfix "/<anon>:" identity;
              mod =
                if isAnon then
                  lib.setDefaultModuleLocation loc param.module
                else
                  {
                    key = loc;
                    _file = loc;
                    imports = [ param.module ];
                  };
            in
            {
              resume = null;
              state = state // {
                imports = x: (state.imports x) ++ [ mod ];
              };
            }
        );
    };

  # Accumulates parametric includes whose args aren't available yet.
  # Deferred includes are drained by drain-deferred when context widens.
  deferredIncludeHandler = {
    "defer-include" =
      { param, state }:
      {
        resume = [ ];
        state = state // {
          # Thunk chain to survive deepSeq (same pattern as imports).
          deferredIncludes = x: ((state.deferredIncludes or (_: [ ])) x) ++ [ param ];
        };
      };
  };

  # Partitions deferred includes into satisfiable (args now in ctx) and
  # remaining. Returns satisfiable list — caller resolves via aspectToEffect.
  drainDeferredHandler = {
    "drain-deferred" =
      { param, state }:
      let
        ctx = param;
        # Unwrap thunk chain.
        deferred = (state.deferredIncludes or (_: [ ])) null;
        satisfiable = builtins.filter (d: builtins.all (k: builtins.hasAttr k ctx) d.requiredArgs) deferred;
        remaining = builtins.filter (
          d: !(builtins.all (k: builtins.hasAttr k ctx) d.requiredArgs)
        ) deferred;
      in
      {
        resume = satisfiable;
        state = state // {
          # Re-wrap remaining as thunk chain.
          deferredIncludes = _: remaining;
        };
      };
  };

in
{
  inherit
    constraintRegistryHandler
    chainHandler
    classCollectorHandler
    deferredIncludeHandler
    drainDeferredHandler
    ;
}
