# into-transition handler — processes context transitions via handler-closures.
# Handles: into-transition
# Sends: ctx-seen (dedup), resolve-complete (missing transition tombstone),
#        then aspectToEffect with __scopeHandlers-tagged target aspects.
# Cross-providers: if source.provides.${targetKey} exists, tagged and resolved alongside.
# State reads: currentCtx
# External dependency: den.stages (target aspect registry, looked up by transition path)
#                      den.relationships (synthesized onto targets for nested transitions)
#
# Context propagation: transitions tag target aspects with __scopeHandlers.
# aspectToEffect derives scope.provide at point of use to resolve parametric args.
# __ctxId is preserved for fan-out identity/dedup.
{
  lib,
  den,
  ...
}:
let
  fx = den.lib.fx;
  inherit (den.lib.aspects.fx.aspect) aspectToEffect;
  inherit (den.lib.aspects.fx.handlers) constantHandler;

  # Flatten a nested into attrset into a flat list of { path, contexts }.
  flattenInto =
    attrset: prefix:
    lib.concatLists (
      lib.mapAttrsToList (
        name: v:
        let
          path = prefix ++ [ name ];
        in
        if builtins.isList v then
          [
            {
              inherit path;
              contexts = v;
            }
          ]
        else
          flattenInto v path
      ) attrset
    );

  # Resolve a single context value by tagging the target aspect with __ctx
  # and resolving it. For fan-out transitions, each context value's target
  # gets its own inner resolution with independent dedup state.
  resolveContextValue =
    parentCtx: targetAspect: results: newCtx:
    let
      scopedCtx = parentCtx // newCtx;
      ctxNames = lib.concatStringsSep "," (
        lib.sort (a: b: a < b) (
          lib.concatMap (
            k:
            let
              v = newCtx.${k};
            in
            if builtins.isAttrs v && v ? name then
              [ v.name ]
            else if builtins.isString v then
              [ v ]
            else if builtins.isInt v || builtins.isFloat v then
              [ (toString v) ]
            else
              [ k ]
          ) (builtins.attrNames newCtx)
        )
      );
      ctxId = ctxNames;
      scopeHandlers = constantHandler scopedCtx;
      tagged = targetAspect // {
        __scopeHandlers = scopeHandlers;
        __ctxId = ctxId;
      };
      _t = builtins.trace "resolveContextValue: target=${targetAspect.name or "?"} scope=${toString (builtins.attrNames scopedCtx)}";
    in
    _t (
      fx.bind (aspectToEffect tagged) (
        childResult:
        # Drain deferred includes now satisfiable with the new context.
        fx.bind (fx.send "drain-deferred" scopedCtx) (
          satisfiable:
          builtins.foldl' (
            acc: d:
            fx.bind acc (
              prevResults:
              let
                deferredTagged = d.child // {
                  __scopeHandlers = scopeHandlers;
                  __ctx = scopedCtx;
                  __ctxId = ctxId;
                };
              in
              fx.bind (aspectToEffect deferredTagged) (resolved: fx.pure (prevResults ++ [ resolved ]))
            )
          ) (fx.pure (results ++ [ childResult ])) satisfiable
        )
      )
    );

  # Resolve a single transition: look up target aspect, check dedup, resolve each context value.
  # Also emits cross-providers: if sourceAspect.provides.${targetKey} exists,
  # that provider is resolved in the scoped context (e.g. flake-system.provides.flake-packages).
  # Build a target aspect from stages + relationships.
  # Stages provide the target's identity (name, provides, includes, class keys).
  # Relationships provide nested transitions (meta.into).
  buildTarget =
    transition:
    let
      stageAspect = lib.attrByPath transition.path null (den.stages or { });

      # Synthesize relationships onto target for nested transitions.
      targetName = if stageAspect != null then stageAspect.name or "" else "";
      relationships = den.relationships or { };
      matchingRels = lib.filter (rel: rel.from == targetName) (builtins.attrValues relationships);
      relationshipInto =
        if matchingRels == [ ] then
          null
        else
          rCtx:
          builtins.foldl' (
            acc: rel:
            let
              targets = rel.resolve rCtx;
              targetList = if builtins.isList targets then targets else [ targets ];
            in
            if targetList == [ ] then acc else acc // { ${rel.to} = (acc.${rel.to} or [ ]) ++ targetList; }
          ) { } matchingRels;
    in
    if stageAspect != null && relationshipInto != null then
      stageAspect
      // {
        meta = (stageAspect.meta or { }) // {
          into = relationshipInto;
        };
      }
    else if stageAspect != null then
      stageAspect
    else
      null;

  resolveTransition =
    targetClass: sourceAspect: currentCtx: results: transition:
    let
      # Include the target class in the dedup key so that the same stage
      # resolved for different class targets (e.g., nixos vs homeManager)
      # is treated as distinct. Without this, host→default (class=nixos)
      # blocks user→default (class=homeManager) via ctx-seen, causing
      # homeManager modules from den.default to never reach the HM pipeline.
      key = "${targetClass}/${lib.concatStringsSep "/" transition.path}";
      targetKey = lib.concatStringsSep "." transition.path;
      effectiveTarget = buildTarget transition;
      sourceProvides = sourceAspect.provides or { };
      crossProvider = sourceProvides.${targetKey} or null;
      # Emit cross-provider result by tagging with __scopeHandlers and resolving.
      isParametricWrapper = v: builtins.isAttrs v && v ? __fn && v ? __args;
      emitCrossProvider =
        scopedCtx: scopeHandlers: ctxId: prevResults:
        if crossProvider != null then
          let
            # Parametric wrappers with named args are resolved by aspectToEffect
            # directly — just tag with scope and pass through.
            # Positional-arg wrappers (__args == {}) must be called with ctx
            # first to get the actual provider function (e.g. _: osFwd becomes osFwd).
            wrapped =
              if isParametricWrapper crossProvider && crossProvider.__args != { } then
                crossProvider
                // {
                  __scopeHandlers = scopeHandlers;
                  __ctx = scopedCtx;
                  __ctxId = ctxId;
                }
              else
                let
                  # For parametric wrappers with empty args, call __fn with ctx.
                  # For bare functions, call directly.
                  rawFn = if isParametricWrapper crossProvider then crossProvider.__fn else crossProvider;
                  crossProviderArgs = lib.functionArgs rawFn;
                  crossCtx =
                    if crossProviderArgs != { } then builtins.intersectAttrs crossProviderArgs scopedCtx else scopedCtx;
                  crossResult = rawFn crossCtx;
                in
                if lib.isFunction crossResult && !builtins.isAttrs crossResult then
                  {
                    name = "${sourceAspect.name or "?"}.provides.${targetKey}";
                    meta = crossProvider.meta or { };
                    __fn = crossResult;
                    __args = lib.functionArgs crossResult;
                    __scopeHandlers = scopeHandlers;
                    __ctx = scopedCtx;
                    __ctxId = ctxId;
                  }
                else
                  crossResult
                  // {
                    __scopeHandlers = scopeHandlers;
                    __ctx = scopedCtx;
                    __ctxId = ctxId;
                  };
          in
          fx.bind (aspectToEffect wrapped) (crossResolved: fx.pure (prevResults ++ [ crossResolved ]))
        else
          fx.pure prevResults;
    in
    if effectiveTarget == null && crossProvider == null then
      # No target ctx node and no cross-provider — emit tombstone.
      let
        ts = {
          name = "~<missing-transition:${key}>";
          meta = {
            excluded = true;
            transitionMissing = true;
            transitionPath = key;
          };
          includes = [ ];
        };
      in
      fx.bind (fx.send "resolve-complete" ts) (_: fx.pure (results ++ [ ts ]))
    else
      let
        # For fan-out transitions (multiple contexts), use per-context
        # dedup keys so each context gets its own resolution. For
        # single-context transitions, use the plain target key.
        isFanOut = builtins.length transition.contexts > 1;
      in
      builtins.foldl' (
        acc: newCtx:
        fx.bind acc (
          innerResults:
          let
            scopedCtx = currentCtx // newCtx;
            # Compute ctxId for cross-provider identity (same derivation
            # as resolveContextValue uses for the target aspect).
            ctxNames = lib.concatStringsSep "," (
              lib.sort (a: b: a < b) (
                lib.concatMap (
                  k:
                  let
                    v = newCtx.${k};
                  in
                  if builtins.isAttrs v && v ? name then
                    [ v.name ]
                  else if builtins.isString v then
                    [ v ]
                  else if builtins.isInt v || builtins.isFloat v then
                    [ (toString v) ]
                  else
                    [ k ]
                ) (builtins.attrNames newCtx)
              )
            );
            # For fan-out, include ctxId in dedup key so each
            # context resolves independently.
            ctxKey = if isFanOut then "${key}/{${ctxNames}}" else key;
            # Build handler-closure for this transition context.
            scopeHandlers = constantHandler scopedCtx;
            # Update state.currentCtx so nested transitions' intoFn
            # receives accumulated context.
            updateCtx = fx.effects.state.modify (st: st // { currentCtx = _: scopedCtx; });
            # For fan-out transitions, resolve the target in a SEPARATE
            # pipeline (fresh dedup state) so inner transitions within each
            # context don't block across contexts. The separate pipeline's
            # imports are merged into the current pipeline's state.
            withTarget =
              if effectiveTarget != null then
                if isFanOut && targetClass == "flake" then
                  let
                    tagged = effectiveTarget // {
                      __scopeHandlers = scopeHandlers;
                      __ctxId = ctxNames;
                    };
                    targetClass' = targetClass;
                    subResult = den.lib.aspects.fx.pipeline.fxFullResolve {
                      class = targetClass';
                      self = tagged;
                      ctx = scopedCtx;
                    };
                    subImports = subResult.state.imports null;
                    mergeImports = fx.effects.state.modify (
                      st:
                      st
                      // {
                        imports = x: (st.imports x) ++ subImports;
                      }
                    );
                  in
                  fx.bind mergeImports (_: fx.pure innerResults)
                else
                  resolveContextValue currentCtx effectiveTarget innerResults newCtx
              else
                fx.pure innerResults;
          in
          fx.bind (fx.send "ctx-seen" ctxKey) (
            { isFirst }:
            if !isFirst then
              fx.pure innerResults
            else
              fx.bind updateCtx (
                _:
                fx.bind withTarget (targetResults: emitCrossProvider scopedCtx scopeHandlers ctxNames targetResults)
              )
          )
        )
      ) (fx.pure results) transition.contexts;

  transitionHandler = {
    "into-transition" =
      { param, state }:
      let
        sourceAspect = param.self;
        # currentCtx is wrapped in a thunk (_: ctx) to survive deepSeq.
        rootCtx = (state.currentCtx or (_: { })) null;
        # Merge the source aspect's __ctx so that stages resolved with
        # explicit context (e.g. resolveStage "user" {host, user}) have
        # their context available for evaluating the into function.
        # Without this, the separate HM pipeline starts with empty ctx
        # and relationship guards like (ctx ? user) fail.
        aspectCtx = sourceAspect.__ctx or { };
        currentCtx = rootCtx // aspectCtx;
        intoResult = param.intoFn currentCtx;
        transitions = flattenInto intoResult [ ];
        targetClass = state.class or "nixos";
      in
      {
        resume = builtins.foldl' (
          acc: transition:
          fx.bind acc (results: resolveTransition targetClass sourceAspect currentCtx results transition)
        ) (fx.pure [ ]) transitions;
        inherit state;
      };
  };

in
{
  inherit transitionHandler;
}
