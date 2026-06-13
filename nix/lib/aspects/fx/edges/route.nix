# route.nix — the simple-route edge constructor (spec §3c "edge collection",
# §B Decision 4 matrix). A `scopedRoutes` simple-route spec becomes a delivery
# edge per the §B 10-cell reachable matrix; the edge's MODE (merge | nest |
# nest-verbatim) and edge PROPERTIES (adaptArgs, guard, #572-combine,
# ensureTargetPath, adapterKey, instantiate, collectSubtree, to=parent) drive
# the materializer's mode switch (edges/materialize.nix). No new modes — the §B
# hybrids decompose into mode + properties.
#
# This file owns the SIMPLE-route half only. Complex (__complexForward) routes
# are dispatched by route/apply.nix:applyComplexRoute (Task 9, synthesize edges)
# and never reach here.
#
# Two projections share ONE classification (classifyRoute):
#   - the trace-facing edge RECORD (identity + annotations, no content) consumed
#     by the read-only oracle (edge-trace.nix) — §8 records identity, not content;
#   - the MATERIALIZATION (the actual wrapped module list + target scope) consumed
#     by route/apply.nix's fold, replacing applySimpleRoute.
# Both derive from the same per-route cell decision, so oracle and production can
# never disagree on which §B cell a route is.
#
# Ordering + dedup (§B Decision 5 + dedupRoutes suppressions) live HERE, at edge
# construction: dedupRoutes' two suppressions (adapterKey@scope identity dedup;
# redundant-root edge-set shadowing) and topoSortRoutes' producer→consumer order
# (now a general edge toposort with loud cycle throw).
{ lib, ... }:
let
  inherit (import ./edge.nix { inherit lib; })
    mkEdge
    collected
    synthesize
    rootTarget
    ;
  inherit (import ../scope-walk.nix { inherit lib; }) subtreeScopes;

  # ===== materialization mechanics (ported from route/wrap.nix) ==========
  # These are MODE mechanics (how `nest`/`nest-verbatim` place a module at P),
  # not mechanism vocabulary. They are invoked by the materializer's mode switch
  # via the closure each edge carries.

  # Freeform type for route nesting evalModules: merges like NixOS (attrsets
  # deep-merge, lists concatenate) but errors on conflicting scalar/derivation
  # values instead of silently clobbering.
  mergeableType = lib.mkOptionType {
    name = "mergeable";
    description = "auto-merged value (attrsets merge, lists concatenate, scalars conflict)";
    merge =
      loc: defs:
      let
        values = map (d: d.value) defs;
        first = builtins.head values;
        allLists = builtins.all builtins.isList values;
        # Derivations are attrsets but must not deep-merge — treat as opaque.
        allMergeableAttrs = builtins.all (v: builtins.isAttrs v && !(lib.isDerivation v)) values;
      in
      if builtins.length defs == 1 then
        first
      else if allLists then
        builtins.concatLists values
      else if allMergeableAttrs then
        (lib.types.lazyAttrsOf mergeableType).merge loc defs
      else
        throw "den: the option `${lib.showOption loc}' has conflicting definitions from multiple aspects";
  };
  nestingFreeformType = lib.types.lazyAttrsOf mergeableType;

  # Adapt a module's args when path is empty (top-level adaptArgs).
  adaptModule =
    adaptArgs: path: mod:
    if adaptArgs == null || path != [ ] then
      mod
    else if builtins.isFunction mod then
      args: mod (adaptArgs args)
    else
      mod;

  # Nest a module at a path using submodule evaluation with adapted specialArgs.
  nestWithAdaptArgs =
    path: adaptArgs: mod: args:
    let
      fullArgs = args // (args.config._module.args or { });
      adapted = adaptArgs fullArgs;
      sourceModules = if builtins.isAttrs mod && mod ? imports then mod.imports else [ mod ];
      evaluated = lib.evalModules {
        specialArgs = adapted;
        modules = [
          { config._module.freeformType = nestingFreeformType; }
        ]
        ++ sourceModules;
      };
    in
    {
      config = lib.setAttrByPath path (
        builtins.removeAttrs evaluated.config [
          "_module"
          "warnings"
          "assertions"
        ]
      );
    };

  # Nest a module at a path by evaluating imports with full outer args.
  nestPlain =
    path: mod: args:
    let
      fullArgs = args // (args.config._module.args or { });
      resolveImport = imp: if builtins.isFunction imp then imp fullArgs else imp;
      sourceModules = if builtins.isAttrs mod && mod ? imports then mod.imports else [ mod ];
      resolved = map resolveImport sourceModules;
      evaluated = lib.evalModules {
        specialArgs = fullArgs;
        modules = [
          { config._module.freeformType = nestingFreeformType; }
        ]
        ++ resolved;
      };
    in
    {
      config = lib.setAttrByPath path (
        builtins.removeAttrs evaluated.config [
          "_module"
          "warnings"
          "assertions"
        ]
      );
    };

  # Nest a module at a path BY REFERENCE, keeping the collected wrapper INTACT
  # (key/_file preserved) — required when the target re-instantiates the
  # delivered content as its own NixOS system (nest-verbatim mode).
  nestVerbatim = path: mod: {
    config = lib.setAttrByPath path { imports = [ mod ]; };
  };

  # Wrap a module with a conditional guard. A bool guard gates content with
  # optionalAttrs (not mkIf): a false guard contributes NOTHING. A structural
  # module (imports/_file but no flat config) recurses, gating each leaf's config.
  guardModule =
    guard: mod:
    if guard == null then
      mod
    else
      let
        guardOne =
          node: args:
          let
            inner = if builtins.isFunction node then node args else node;
          in
          if inner ? imports && !(inner ? config) then
            { imports = map guardOne inner.imports; } // builtins.removeAttrs inner [ "imports" ]
          else
            { config = lib.optionalAttrs (guard args) (inner.config or inner); };
      in
      guardOne mod;

  # The §B nest/nest-verbatim placement for ONE collected module at P.
  #   reinstantiate ⇒ nest-verbatim; adaptArgs (path≠[]) ⇒ nestWithAdaptArgs;
  #   else nestPlain. P=[] returns the module unchanged (merge contribution).
  placeOne =
    {
      path,
      adaptArgs,
      reinstantiate,
      guard,
    }:
    mod:
    let
      placed =
        if path == [ ] then
          mod
        else if reinstantiate then
          nestVerbatim path mod
        else if adaptArgs != null then
          nestWithAdaptArgs path adaptArgs mod
        else
          nestPlain path mod;
    in
    guardModule guard placed;

  # The §B materialization for a simple route's collected source modules → the
  # wrapped module list landed in the target bucket. Implements the §B cells:
  #   - empty source: ensureTargetPath (cell 5) or no edge.
  #   - #572 combine (cell 3): adaptArgs≠null ∧ path≠[] ∧ ¬reinstantiate ⇒ ONE
  #     nestWithAdaptArgs over { imports = adapted; } (all modules in one
  #     evalModules so same-class aspects merge inside it).
  #   - otherwise (cells 1/2/4): per-module placement.
  # adapterKey (cell 6) and instantiate (cell 7) are handled by the constructor
  # BEFORE this (they replace the source-module list outright); this function
  # sees only the wrapRouteModules path.
  materializeNest =
    {
      modules,
      path,
      guard ? null,
      adaptArgs ? null,
      reinstantiate ? false,
      ensureTargetPath ? false,
    }:
    let
      adapted = map (adaptModule adaptArgs path) modules;
    in
    if adaptArgs != null && path != [ ] && !reinstantiate then
      # cell 3 (#572): ONE combined evalModules.
      [
        (guardModule guard (nestWithAdaptArgs path adaptArgs { imports = adapted; }))
      ]
    else
      map (placeOne {
        inherit
          path
          adaptArgs
          reinstantiate
          guard
          ;
      }) adapted;

  # ===== adapter functor (§B cell 6 — dynamic P) =========================
  # The adapter arm's P is DYNAMIC: resolved at evalModules time via intoPathFn
  # args, not at construction. The edge carries the functor recipe; the trace
  # records P as the static route.path with dynamicPath=true.
  mkAdapterFunctor =
    route: sourceModules:
    let
      adapterMod = route.adapterModule or null;
      sourceModule = {
        imports = sourceModules;
      };
      guardFn = route.guard or (_: lib.id);
      adaptArgsFn = route.adaptArgs or (_: { });
      intoPathFn = route.intoPathFn or (_: route.path);
      key = route.adapterKey;
      guardArgs = route.guardArgs or { };
      intoPathArgs = route.intoPathArgs or { };
      adaptArgv = route.adaptArgv or { };
      freeformMod =
        route.freeformMod or {
          config._module.freeformType = lib.types.lazyAttrsOf lib.types.unspecified;
        };
      adapterMods =
        if adapterMod != null then
          [
            freeformMod
            adapterMod
          ]
        else
          [ freeformMod ];
    in
    {
      __functionArgs = guardArgs // intoPathArgs // adaptArgv;
      __functor = _: args: {
        options.den.fwd.${key} = lib.mkOption {
          defaultText = lib.literalExpression "{ }";
          default = { };
          type = lib.types.submoduleWith {
            specialArgs = adaptArgsFn args;
            modules = adapterMods ++ [ sourceModule ];
          };
        };
        config = guardFn args (lib.setAttrByPath (intoPathFn args) args.config.den.fwd.${key});
      };
    };

  # ===== source collection (§B cell 9 — collectSubtree / isFlakeRoute) ===
  # Collect class modules from a scope and all descendants, skipping isolated
  # descendants (isolation-AWARE; collection root always included). The plain
  # case collects from the route's own scope only.
  collectFromSubtree =
    wrappedPerScope: scopeParent: scopeIsolated: rootScopeId: fromClass:
    let
      scopes = subtreeScopes {
        inherit scopeParent;
        isolated = scopeIsolated;
        root = rootScopeId;
        allScopeIds = builtins.attrNames wrappedPerScope;
      };
    in
    lib.concatMap (sid: wrappedPerScope.${sid}.${fromClass} or [ ]) scopes;

  sourceModulesOf =
    {
      route,
      wrappedPerScope,
      scopeParent,
      scopeIsolated,
    }:
    let
      isFlakeRoute = route.intoClass == "flake";
    in
    if isFlakeRoute || (route.collectSubtree or false) then
      collectFromSubtree wrappedPerScope scopeParent scopeIsolated route.sourceScopeId route.fromClass
    else if wrappedPerScope ? ${route.sourceScopeId} then
      wrappedPerScope.${route.sourceScopeId}.${route.fromClass} or [ ]
    else
      [ ];

  # ===== per-route classification (§B Decision 4 matrix) =================
  # The single cell decision both projections derive from. `mode` is the §B
  # M; `kind` selects the materialization arm (wrapRouteModules | adapter |
  # instantiate); `props` are the trace annotations / materializer properties.
  classifyRoute =
    route:
    let
      path = route.path or [ ];
      isFlakeRoute = route.intoClass == "flake";
      hasInstantiate = (route.instantiate or null) != null;
      isAdapterRoute = (route.adapterKey or null) != null;
      reinstantiate = route.reinstantiate or false;
      adaptArgs = route.adaptArgs or null;
    in
    {
      inherit
        path
        isFlakeRoute
        hasInstantiate
        isAdapterRoute
        reinstantiate
        adaptArgs
        ;
      # §B mode: reinstantiate ⇒ nest-verbatim; P=[] ⇒ merge; else nest.
      mode =
        if reinstantiate then
          "nest-verbatim"
        else if path == [ ] then
          "merge"
        else
          "nest";
      appendToParent = route.appendToParent or false;
      collectSubtree = route.collectSubtree or false;
      adapterKey = route.adapterKey or null;
      guard = route.guard or null;
    };

  # The target scope for a route's edge: appendToParent ⇒ the PARENT scope of
  # sourceScopeId (the §B "to=parent" property, consumed at construction).
  appendScopeIdOf =
    scopeParent: route:
    if route.appendToParent or false then
      scopeParent.${route.sourceScopeId} or route.sourceScopeId
    else
      route.sourceScopeId;

  # ===== dedup + toposort (§B Decision 5 + dedupRoutes suppressions) =====

  # adapterKeys that exist at child (non-root) scopes — the redundant-root shadow
  # input.
  findChildScopeKeys =
    rootScopeId: rawRoutes:
    builtins.foldl' (
      acc: r:
      let
        ak = r.adapterKey or null;
      in
      if ak != null && rootScopeId != null && r.sourceScopeId != rootScopeId then
        acc // { ${ak} = true; }
      else
        acc
    ) { } rawRoutes;

  # Per-position suppression verdict for each raw route, matching dedupRoutes'
  # two rules (redundant-root shadow + adapterKey@scope first-wins). Returns a
  # list aligned with rawRoutes: { suppressed; byChild; adapterKey; }.
  suppressionVerdicts =
    rootScopeId: rawRoutes:
    let
      childScopeKeys = findChildScopeKeys rootScopeId rawRoutes;
      go =
        seen: routes:
        if routes == [ ] then
          [ ]
        else
          let
            r = builtins.head routes;
            rest = builtins.tail routes;
            ak = r.adapterKey or null;
            # §B rule 2: redundant-root shadow — an adapter route AT the root
            # whose adapterKey also exists at a child scope is dropped.
            isRedundantRoot =
              ak != null && rootScopeId != null && r.sourceScopeId == rootScopeId && childScopeKeys ? ${ak};
            # §B rule 1: same adapterKey@scope first-occurrence wins.
            key = if ak != null then "${ak}@${r.sourceScopeId}" else null;
            isDupKey = key != null && seen ? ${key};
            suppressed = isRedundantRoot || isDupKey;
            verdict = {
              inherit suppressed;
              byChild = isRedundantRoot;
              adapterKey = ak;
            };
            nextSeen = if !suppressed && key != null then seen // { ${key} = true; } else seen;
          in
          [ verdict ] ++ go nextSeen rest;
    in
    go { } rawRoutes;

  # The kept (non-suppressed) routes in original order — the §B Decision 5
  # toposort input.
  keptRoutes =
    rootScopeId: rawRoutes:
    let
      verdicts = suppressionVerdicts rootScopeId rawRoutes;
    in
    builtins.concatLists (
      lib.imap0 (i: r: lib.optional (!(builtins.elemAt verdicts i).suppressed) r) rawRoutes
    );

  # General edge toposort (§B Decision 5): a producer (intoClass@scope) must fire
  # before any consumer (fromClass@scope) that reads it. Today this is the
  # single-level partition topoSortRoutes did (a complex forward depending on a
  # producer of its fromClass), generalized to a real toposort with a LOUD cycle
  # throw printing the edge chain. Simple routes read the original per-scope data
  # (not the fold state), so they never participate as dependents.
  topoSort =
    routes:
    let
      n = builtins.length routes;
      routeAt = i: builtins.elemAt routes i;
      producerMap = builtins.foldl' (
        acc: i:
        let
          r = routeAt i;
          key = "${r.intoClass}@${r.sourceScopeId}";
        in
        acc // { ${key} = (acc.${key} or [ ]) ++ [ i ]; }
      ) { } (lib.range 0 (n - 1));
      # Dependency indices of route i: producers of its fromClass@scope OTHER than
      # itself, but only when i is a complex forward (simple routes read the
      # original per-scope data, never the fold state, so never depend).
      depsOf =
        i:
        let
          r = routeAt i;
        in
        if (r.__complexForward or false) then
          builtins.filter (j: j != i) (producerMap."${r.fromClass}@${r.sourceScopeId}" or [ ])
        else
          [ ];
      labelOf =
        i:
        let
          r = routeAt i;
        in
        "${r.fromClass or "?"}>${r.intoClass or "?"}@${r.sourceScopeId or "?"}";
      # Kahn-style toposort over the INDEX DAG (indices are comparable; route
      # records may carry functions and are not). On a remaining cycle, throw with
      # the participating class@scope edge chain (§B Decision 5: a detected cycle
      # is a loud config error). Today no cycle is reachable — single-level
      # producer→consumer — so this is a forward guard, byte-stable with the old
      # noDeps-before-withDeps partition.
      emittedSet = is: lib.genAttrs (map toString is) (_: true);
      go =
        emitted: remaining:
        if remaining == [ ] then
          [ ]
        else
          let
            es = emittedSet emitted;
            ready = builtins.filter (i: builtins.all (j: es ? ${toString j}) (depsOf i)) remaining;
          in
          if ready == [ ] then
            throw "den materialize: delivery-edge cycle among [ ${lib.concatStringsSep " -> " (map labelOf remaining)} ] — a route's source depends on its own output transitively."
          else
            let
              readySet = lib.genAttrs (map toString ready) (_: true);
            in
            ready ++ go (emitted ++ ready) (builtins.filter (i: !(readySet ? ${toString i})) remaining);
    in
    map routeAt (go [ ] (lib.range 0 (n - 1)));

  # The ordered, deduped route list both projections fold over. Suppressed routes
  # are DROPPED for materialization but RECORDED (with suppressed=true) for the
  # trace — so the two consumers pass the full raw list + verdicts and select.
  orderedKeptRoutes = rootScopeId: rawRoutes: topoSort (keptRoutes rootScopeId rawRoutes);
in
{
  inherit
    materializeNest
    mkAdapterFunctor
    sourceModulesOf
    classifyRoute
    appendScopeIdOf
    suppressionVerdicts
    findChildScopeKeys
    keptRoutes
    orderedKeptRoutes
    topoSort
    ;
  # Compat alias: the old apply.nix `dedupRoutes` returned the kept (non-
  # suppressed) routes in original order — exactly keptRoutes. Retained for the
  # route/default.nix re-export; the extractor now consumes routeEdges directly.
  dedupRoutes = keptRoutes;

  # ===== trace-facing route edge constructor (§8 identity, no content) ===
  # Renders the simple+complex route specs as edge RECORDS for the oracle
  # (edge-trace.nix). Identity + annotations only; suppression verdicts are now
  # EXACT (the constructor's own dedup rules), not the v0 path-dependent
  # approximation. sourceVia for complex forwards stays "unresolved" (Task 9).
  #
  #   name        — sid → stable scope name (edge.nix scopeName).
  #   scopeParent — parent DAG (for appendToParent target resolution).
  #   rootScopeId — the pipeline root (suppression rootScopeId).
  #   rawRoutes   — the flattened scopedRoutes spec list.
  routeEdges =
    {
      name,
      scopeParent,
      rootScopeId,
      rawRoutes,
    }:
    let
      verdicts = suppressionVerdicts rootScopeId rawRoutes;
      forwardId =
        spec:
        spec.adapterKey or "${spec.fromClass}>${spec.intoClass}@${spec.sourceScopeId}/${
          lib.concatStringsSep "/" (spec.staticIntoPath or spec.path or [ ])
        }";
      routeEdge =
        verdict: spec:
        let
          sid = spec.sourceScopeId;
          isComplex = spec.__complexForward or false;
          path = spec.path or spec.staticIntoPath or [ ];
          appendToParent = spec.appendToParent or false;
          appendSid = if appendToParent then scopeParent.${sid} or sid else sid;
          adapterKey = spec.adapterKey or null;
          reinstantiate = spec.reinstantiate or false;
          baseAnnotations =
            lib.optionalAttrs (spec.adaptArgs or null != null) { adaptArgs = true; }
            // lib.optionalAttrs (spec.guard or null != null) { guard = true; }
            // lib.optionalAttrs (spec.collectSubtree or false) { collectSubtree = true; }
            // lib.optionalAttrs ((spec.intoClass or null) == "flake") { isFlakeRoute = true; }
            // lib.optionalAttrs ((spec.instantiate or null) != null) { instantiate = true; }
            // lib.optionalAttrs appendToParent { appendToParent = true; }
            // lib.optionalAttrs (
              # §B cell 5: ensureEntry placeholder (empty target path materialized).
              # Content-blind approx (also requires empty module set) — converges
              # with the materializer's actual ensureTargetPath at runtime.
              !isComplex && (spec.intoClass or null) != "flake" && (spec.adaptArgs or null) != null && path != [ ]
            ) { ensureTargetPath = true; }
            // lib.optionalAttrs verdict.suppressed { suppressed = true; }
            // lib.optionalAttrs verdict.byChild { suppressedByChildKey = adapterKey; };
        in
        if isComplex then
          mkEdge {
            source = synthesize (forwardId spec) spec.fromClass spec.intoClass;
            target = rootTarget (name appendSid) spec.intoClass;
            inherit path;
            mode = "nest";
            annotations = baseAnnotations // {
              complexForward = true;
              sourceVia = "unresolved";
            };
          }
        else
          mkEdge {
            source = collected (name sid) spec.fromClass;
            target = rootTarget (name appendSid) spec.intoClass;
            inherit path;
            mode =
              if reinstantiate then
                "nest-verbatim"
              else if path == [ ] then
                "merge"
              else
                "nest";
            annotations =
              baseAnnotations
              // lib.optionalAttrs (adapterKey != null) {
                inherit adapterKey;
                dynamicPath = true;
              };
          };
    in
    lib.imap0 (i: spec: routeEdge (builtins.elemAt verdicts i) spec) rawRoutes;
}
