# Node-spawn primitive.
#
# A spawned node is an independent resolution node spawned from a parent
# (host) scope, threaded with the parent pipeline's resolved scope-tree state
# (host + ALL siblings) so its OWN assemblePipes pass re-derives
# inherited/collected pipe values with full fleet visibility. den-hoag: a
# `spawn` with one read-only inherited edge (neededBy the parent's resolved
# state) — parallel-schedulable, not a sequential route fold.
{ lib, den }:
let
  inherit (import ./assemble-pipes.nix { inherit lib den; }) assemblePipes;
  pipeNamesSet = lib.genAttrs (builtins.attrNames (den.quirks or { })) (_: true);
in
{
  # Phase helpers (wrapPerScope/applyProvides/applyRoutes) and the recursive
  # nested-route resolver (selfRef) are injected to avoid a resolve.nix import
  # cycle. mkPipeline + parentState are captured once per run; the inner
  # { from, class, aspect, bindings } call materializes a single class.
  mkSpawnNode =
    {
      wrapPerScope,
      applyProvides,
      applyRoutes,
      normalizeRoot,
      ctxFromHandlers,
      selfRef,
    }:
    mkPipeline: parentState:
    {
      from,
      class,
      aspect,
      bindings ? { },
    }:
    let
      normalized = normalizeRoot aspect;
      seedCtx =
        (parentState.scopeContexts.${from} or parentState.ctx)
        // ctxFromHandlers (aspect.__scopeHandlers or { })
        // bindings;

      # 1. Walk the aspect for the single target class -> the spawned subtree state.
      result = mkPipeline { inherit class; } {
        self = normalized;
        ctx = seedCtx;
      };
      spawnRoot = result.state.rootScopeId;

      # The spawn root must be a distinct child of `from`. A self-parent edge
      # (spawnRoot == from) collapses policyBoundAncestor to null -> zero peers,
      # silently reproducing the single-host bug. Throw with context (not a bare
      # assert) so a future regression names the collapsed scope and its cause.
      _assertRoot =
        if spawnRoot != from then
          null
        else
          throw "den: spawnNode spawn root equals its parent scope '${from}' — a self-parent edge collapses policyBoundAncestor to null and yields zero fleet peers. The seed ctx likely lost its child binding (e.g. `user`).";

      mergedPipeEffects = parentState.scopedPipeEffects // (result.state.scopedPipeEffects null);

      # A pipe `pn` is host-bound when the host scope (`from`) or one of its
      # ancestors ran a pipe policy effect for it (e.g. a fleet `collectAll`).
      ancestorBoundPipe =
        pn:
        let
          go =
            sid:
            if sid == null || sid == spawnRoot then
              false
            else if builtins.any (e: e.pipeName == pn) (mergedPipeEffects.${sid} or [ ]) then
              true
            else
              go (parentState.scopeParent.${sid} or null);
        in
        go from;

      # The node walk re-emits the host aspect's pipe-named keys (e.g.
      # `host-addrs`) at the spawn root. For a HOST-BOUND pipe, that local
      # re-emission makes the spawned scope bind the pipe locally (a self-only
      # value), shadowing inheritance of the host's policy-assembled value
      # (e.g. a fleet collectAll). The spawned scope is a pure consumer there, so
      # strip those keys and let policyBoundAncestor inherit the host's value.
      # Pipes with NO host-bound policy (a plain local emit-and-consume within
      # the host aspect tree) keep their local emission — there is no ancestor
      # value to inherit. Class keys (homeManager, nixos, …) are always kept.
      strippableNames = builtins.filter ancestorBoundPipe (builtins.attrNames pipeNamesSet);
      spawnedClassImports = lib.mapAttrs (
        _: scopeClasses: builtins.removeAttrs scopeClasses strippableNames
      ) (result.state.scopedClassImports null);

      # 2. Merge parent state (host + siblings) under the spawned subtree, linking
      #    the spawn root up to `from` so scopeParent walks reach the host's
      #    policy-bound pipes and collectAll scans the fleet siblings.
      mergedScopeContexts = parentState.scopeContexts // (result.state.scopeContexts null);
      mergedClassImports = parentState.scopedClassImports // spawnedClassImports;
      mergedScopeParent =
        parentState.scopeParent
        // (result.state.scopeParent null)
        // {
          ${spawnRoot} = from;
        };

      # 3. Re-derive pipes over merged state. hostConfigs = null: config-dependent
      #    stay deferred (via __configThunk); pipeline-parametric resolve eagerly.
      augmented = builtins.seq _assertRoot (assemblePipes {
        scopeContexts = mergedScopeContexts;
        scopedClassImports = mergedClassImports;
        scopedPipeEffects = mergedPipeEffects;
        scopeParent = mergedScopeParent;
        scopeEntityKind = parentState.scopeEntityKind;
        hostConfigs = null;
      });

      # 4. Phases 1-3 over the spawned subtree; class isolation -> one class emitted.
      phase1 = wrapPerScope parentState.ctx augmented mergedClassImports;
      phase2 = applyProvides parentState.ctx augmented (result.state.scopedProvides null) phase1;
      phase3 =
        applyRoutes selfRef parentState.ctx augmented spawnRoot mergedScopeParent
          (result.state.scopedRoutes null)
          phase2;

      # Restrict extraction to the spawned subtree (spawnRoot + descendants).
      # phase3.classImports aggregates across ALL merged scopes — including the
      # host and SIBLING user scopes (the pipe-collection peers, and other users
      # on the same host) — so reading it directly would leak a peer user's
      # homeManager content into this node. The fleet pipe values still resolve
      # correctly because assemblePipes ran over the full merged state; only the
      # final per-scope class buckets are subtree-restricted here.
      isInSubtree =
        sid:
        sid == spawnRoot
        || (
          let
            parent = mergedScopeParent.${sid} or null;
          in
          parent != null && parent != sid && isInSubtree parent
        );
      subtreeScopes = builtins.filter isInSubtree (builtins.attrNames phase3.perScope);
    in
    {
      imports = lib.concatMap (sid: phase3.perScope.${sid}.${class} or [ ]) subtreeScopes;
    };
}
