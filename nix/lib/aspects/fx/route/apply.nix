# Apply registered routes — fold over deduped + toposorted route specs,
# dispatching complex (forward-derived, Task 9) vs simple (delivery-edge, Task 8).
#
# Simple routes are now DELIVERY EDGES: their §B-matrix classification, dedup,
# ordering, and source collection live in edges/route.nix; their nest /
# nest-verbatim / merge materialization lives in edges/materialize.nix's mode
# switch (materializeRouteEdge). This file keeps only the COMPLEX-forward
# (synthesize) path inline (filterRootModules / getCollectedSource /
# resolveSourceFallback / mkAdapterFunctor-for-complex), which Task 9 ports.
{
  lib,
  den,
  collectClassMods,
}:
let
  routeEdges = import ../edges/route.nix { inherit lib; };
  inherit (import ../edges/materialize.nix { inherit lib; }) materializeRouteEdge;
  inherit (routeEdges)
    classifyRoute
    sourceModulesOf
    appendScopeIdOf
    orderedKeptRoutes
    ;

  # Root-scope `fromClass` content a child-scope COMPLEX forward may pull in.
  # When `fromClass` is owned by an entity in the chain, root content under it is
  # that entity's own declaration, not aggregation fodder — restrict to shared
  # `den.default`. A forward-only custom class keeps its full root content.
  filterRootModules =
    scopeContexts: spec: rootModules: isDenDefaultModule:
    let
      childCtx = scopeContexts.${spec.sourceScopeId} or { };
      ownedClasses =
        (childCtx.user.classes or [ ])
        ++ lib.optional (childCtx ? host) childCtx.host.class
        ++ lib.optional (childCtx ? home) childCtx.home.class;
    in
    if builtins.elem spec.fromClass ownedClasses then
      builtins.filter isDenDefaultModule rootModules
    else
      rootModules;

  getCollectedSource =
    acc: spec: rootScopeId: isDenDefaultModule: scopeContexts:
    let
      sid = spec.sourceScopeId;
    in
    if rootScopeId != null && sid != rootScopeId then
      let
        ownModules = (acc.perScope.${sid} or { }).${spec.fromClass} or [ ];
        rootModules = (acc.perScope.${rootScopeId} or { }).${spec.fromClass} or [ ];
      in
      filterRootModules scopeContexts spec rootModules isDenDefaultModule ++ ownModules
    else
      acc.classImports.${spec.fromClass} or [ ];

  resolveSourceFallback =
    spec: spawnNode: scopeParent: scopeContexts: ctx:
    if !(spec ? sourceAspect) || spawnNode == null || !(spec ? sourceScopeId) then
      [ ]
    else
      (spawnNode {
        from = scopeParent.${spec.sourceScopeId} or spec.sourceScopeId;
        class = spec.fromClass;
        aspect = den.lib.aspects.normalizeRoot spec.sourceAspect;
        bindings = { };
      }).imports;

  appendToClass = acc: cls: sid: newMods: {
    classImports = acc.classImports // {
      ${cls} = (acc.classImports.${cls} or [ ]) ++ newMods;
    };
    perScope = acc.perScope // {
      ${sid} = (acc.perScope.${sid} or { }) // {
        ${cls} = ((acc.perScope.${sid} or { }).${cls} or [ ]) ++ newMods;
      };
    };
  };

  # Task 9: scheduled deletion (complex-forward port).
  applyComplexRoute =
    acc:
    {
      route,
      rootScopeId,
      scopeContexts,
      scopeParent,
      ctx,
      spawnNode,
      buildForwardAspect,
      isDenDefaultModule,
    }:
    let
      spec = route;
      collected = getCollectedSource acc spec rootScopeId isDenDefaultModule scopeContexts;
      sourceModules =
        if collected != [ ] then
          collected
        else
          resolveSourceFallback spec spawnNode scopeParent scopeContexts ctx;
      sourceModule = spec.mapModule { imports = sourceModules; };
      newMods = collectClassMods spec.intoClass (buildForwardAspect spec sourceModule);
    in
    appendToClass acc spec.intoClass spec.sourceScopeId newMods;

  isDenDefaultModule = mod: lib.hasSuffix "@default" (mod.key or mod._file or "");

  # Simple route → delivery edge → materialized module list, appended to the
  # target bucket. The §B cell decision (classifyRoute), source collection
  # (sourceModulesOf), and target scope (appendScopeIdOf) come from
  # edges/route.nix; the nest/nest-verbatim/merge placement from
  # materializeRouteEdge (the mode switch).
  applySimpleRoute =
    acc:
    {
      route,
      wrappedPerScope,
      scopeParent,
      scopeIsolated,
    }:
    let
      c = classifyRoute route;
      sourceModules = sourceModulesOf {
        inherit
          route
          wrappedPerScope
          scopeParent
          scopeIsolated
          ;
      };
      adapterMod = route.adapterModule or null;
      modulesWithAdapter = if adapterMod == null then sourceModules else sourceModules ++ [ adapterMod ];
      # The §B materialize payload selecting the cell arm.
      kind =
        if c.hasInstantiate then
          "instantiate"
        else if modulesWithAdapter == [ ] then
          "ensure-empty"
        else if c.isAdapterRoute then
          "adapter"
        else
          "nest";
      # cell 5 ensureTargetPath predicate (apply-time, content-aware): empty
      # module set + adaptArgs + non-flake + path≠[].
      ensureTargetPath =
        !c.isFlakeRoute && c.adaptArgs != null && c.path != [ ] && modulesWithAdapter == [ ];
      # cell 7 instantiate: eager evaluation at materialization.
      instantiateEvaluated =
        let
          adaptArgsFn = route.adaptArgs or (_: { });
          extraArgs = adaptArgsFn { };
        in
        if c.hasInstantiate then route.instantiate ({ modules = sourceModules; } // extraArgs) else null;
      wrappedModules = materializeRouteEdge {
        inherit kind ensureTargetPath instantiateEvaluated;
        inherit (c)
          path
          adaptArgs
          guard
          reinstantiate
          ;
        modules = modulesWithAdapter;
        sourceModules = sourceModules;
        adapterPresent = adapterMod != null;
        adapterRoute = route;
      };
    in
    appendToClass acc route.intoClass (appendScopeIdOf scopeParent route) wrappedModules;

  # Main entry: dedup + toposort routes, fold applying each (complex vs simple).
  applyRoutes =
    {
      scopedRoutes,
      wrappedPerScope,
      classImports,
      scopeParent ? { },
      scopeIsolated ? { },
      scopeContexts ? { },
      ctx ? { },
      spawnNode ? null,
      rootScopeId ? null,
      buildForwardAspect ? null,
    }:
    let
      allRoutes = orderedKeptRoutes rootScopeId (lib.concatLists (lib.attrValues scopedRoutes));
    in
    builtins.foldl'
      (
        acc: route:
        if route.__complexForward or false then
          applyComplexRoute acc {
            inherit
              route
              rootScopeId
              scopeContexts
              scopeParent
              ctx
              spawnNode
              buildForwardAspect
              isDenDefaultModule
              ;
          }
        else
          applySimpleRoute acc {
            inherit
              route
              wrappedPerScope
              scopeParent
              scopeIsolated
              ;
          }
      )
      {
        inherit classImports;
        perScope = wrappedPerScope;
      }
      allRoutes;
in
{
  # applyRoutes is the only consumer-facing entry: the route fold. Simple routes
  # are delivery edges (edges/route.nix + edges/materialize.nix); the old
  # dedupRoutes/findChildScopeKeys exports (consumed by the v0 edge-trace arm)
  # are dead now that the oracle renders routes via the shared routeEdges
  # constructor — dropped here. Suppression/dedup lives in edges/route.nix.
  inherit applyRoutes;
}
