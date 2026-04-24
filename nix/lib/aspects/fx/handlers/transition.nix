# Sends: ctx-seen, resolve-complete, aspectToEffect
# State reads: currentCtx
# External: den.stages (target registry), den.policies (nested transitions)
{
  lib,
  den,
  ...
}:
let
  fx = den.lib.fx;
  inherit (den.lib.aspects.fx.aspect) aspectToEffect;
  inherit (den.lib.aspects.fx.handlers) constantHandler;
  inherit (den.lib.aspects) isParametricWrapper;

  mkCtxId =
    ctx:
    lib.concatStringsSep "," (
      lib.sort (a: b: a < b) (
        lib.concatMap (
          attrName:
          let
            attrVal = ctx.${attrName};
          in
          if builtins.isAttrs attrVal && attrVal ? name then
            [ attrVal.name ]
          else if builtins.isString attrVal then
            [ attrVal ]
          else if builtins.isInt attrVal || builtins.isFloat attrVal then
            [ (toString attrVal) ]
          else
            [ attrName ]
        ) (builtins.attrNames ctx)
      )
    );

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
      ctxId = mkCtxId newCtx;
      scopeHandlers = constantHandler scopedCtx;
      tagged = targetAspect // {
        __scopeHandlers = scopeHandlers;
        __ctx = scopedCtx;
        __ctxId = ctxId;
      };
    in
    fx.bind (aspectToEffect tagged) (
      childResult:
      # Drain deferred includes now satisfiable with the new context.
      # Note: drained includes go through aspectToEffect which re-checks
      # constraints via check-constraint. Constraints registered AFTER the
      # original deferral will apply — this is intentional (constraints are global).
      fx.bind (fx.send "drain-deferred" scopedCtx) (
        satisfiable:
        builtins.foldl' (
          acc: deferred:
          fx.bind acc (
            prevResults:
            let
              deferredTagged = deferred.child // {
                __scopeHandlers = scopeHandlers;
                __ctx = scopedCtx;
                __ctxId = ctxId;
              };
            in
            fx.bind (aspectToEffect deferredTagged) (resolved: fx.pure (prevResults ++ [ resolved ]))
          )
        ) (fx.pure (results ++ [ childResult ])) satisfiable
      )
    );

  # Core pipeline effects that policy handlers must not shadow.
  coreEffects = [
    "into-transition"
    "ctx-seen"
    "resolve-complete"
    "emit-class"
    "emit-include"
    "emit-forward"
    "chain-push"
    "chain-pop"
    "check-constraint"
    "register-constraint"
    "defer-include"
    "drain-deferred"
    "get-path-set"
    "has-handler"
    "resolve-policy"
    "resolve-target"
  ];

  collectPolicyHandlers =
    sourceStage: targetKey:
    let
      policies = den.policies or { };
      matching = lib.filter (p: p.from == sourceStage && p.to == targetKey) (
        builtins.attrValues policies
      );
      allHandlers = builtins.foldl' (acc: p: acc // (p.handlers or { })) { } matching;
    in
    builtins.removeAttrs allHandlers coreEffects;

  emitCrossProvider =
    {
      crossProvider,
      sourceAspect,
      targetKey,
    }:
    scopedCtx: scopeHandlers: ctxId: prevResults:
    if crossProvider == null then
      fx.pure prevResults
    else
      let
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
      fx.bind (aspectToEffect wrapped) (crossResolved: fx.pure (prevResults ++ [ crossResolved ]));

  resolveFanOut =
    {
      targetClass,
      effectiveTarget,
      scopedCtx,
      scopeHandlers,
      ctxNames,
    }:
    innerResults:
    let
      tagged = effectiveTarget // {
        __scopeHandlers = scopeHandlers;
        __ctxId = ctxNames;
      };
      fanOutResult = den.lib.aspects.fx.pipeline.fxFullResolve {
        class = targetClass;
        self = tagged;
        ctx = scopedCtx;
      };
      subImports = fanOutResult.state.imports null;
      # state.modify reads st.imports at the modify call site. This is safe
      # because fxFullResolve above is a separate pipeline whose results are
      # fully materialized before the modify runs. No concurrent handlers
      # can append to imports between construction and handling.
      mergeImports = fx.effects.state.modify (st: st // { imports = x: (st.imports x) ++ subImports; });
    in
    fx.bind mergeImports (_: fx.pure innerResults);

  resolveTransition =
    targetClass: sourceAspect: currentCtx: results: transition:
    let
      key = "${targetClass}/${lib.concatStringsSep "/" transition.path}";
      targetKey = lib.concatStringsSep "." transition.path;
      sourceProvides = sourceAspect.provides or { };
      crossProvider = sourceProvides.${targetKey} or null;
      emitCross = emitCrossProvider { inherit crossProvider sourceAspect targetKey; };
      policyHandlers = collectPolicyHandlers (sourceAspect.name or "") targetKey;
    in
    fx.bind
      (fx.send "resolve-target" {
        path = transition.path;
        inherit targetClass;
      })
      (
        effectiveTarget:
        if effectiveTarget == null && crossProvider == null then
          let
            tombstone = {
              name = "~<missing-transition:${key}>";
              meta = {
                excluded = true;
                transitionMissing = true;
                transitionPath = key;
              };
              includes = [ ];
            };
          in
          fx.bind (fx.send "resolve-complete" tombstone) (_: fx.pure (results ++ [ tombstone ]))
        else
          let
            isFanOut = builtins.length transition.contexts > 1;
            # Pre-index contexts so fan-out dedup keys are unique even when
            # policy-contributed contexts have identical attr names
            # (e.g., {fromClass=_:"packages"} vs {fromClass=_:"files"}).
            indexedContexts = lib.imap0 (i: ctx: {
              inherit i;
              ctx = ctx;
            }) transition.contexts;
          in
          builtins.foldl' (
            acc: indexed:
            fx.bind acc (
              innerResults:
              let
                newCtx = indexed.ctx;
                scopedCtx = currentCtx // newCtx;
                ctxNames = mkCtxId newCtx;
                ctxKey = if isFanOut then "${key}/{${ctxNames}}#${toString indexed.i}" else key;
                scopeHandlers = constantHandler scopedCtx;
                updateCtx = fx.effects.state.modify (st: st // { currentCtx = _: scopedCtx; });
                baseComputation =
                  if effectiveTarget != null then
                    if isFanOut && targetClass == "flake" then
                      resolveFanOut {
                        inherit
                          targetClass
                          effectiveTarget
                          scopedCtx
                          scopeHandlers
                          ctxNames
                          ;
                      } innerResults
                    else
                      resolveContextValue currentCtx effectiveTarget innerResults newCtx
                  else
                    fx.pure innerResults;
                # Install policy handlers for aspects resolved under this transition.
                # Fan-out sub-pipelines (fxFullResolve) create fresh handler scopes,
                # so policy handlers don't propagate into them. Nested transitions
                # that install handlers for the same effect name use innermost-wins
                # semantics (standard scope.provide shadowing).
                withTarget =
                  if policyHandlers != { } then
                    fx.effects.scope.provide policyHandlers baseComputation
                  else
                    baseComputation;
              in
              fx.bind (fx.send "ctx-seen" ctxKey) (
                { isFirst }:
                if !isFirst then
                  fx.pure innerResults
                else
                  fx.bind updateCtx (
                    _: fx.bind withTarget (targetResults: emitCross scopedCtx scopeHandlers ctxNames targetResults)
                  )
              )
            )
          ) (fx.pure results) indexedContexts
      );

  maxTransitionDepth = 50;

  transitionHandler = {
    "into-transition" =
      { param, state }:
      let
        sourceAspect = param.self;
        rootCtx = (state.currentCtx or (_: { })) null;
        # Merge the source aspect's __ctx so that stages resolved with
        # explicit context have their context available for the into function.
        aspectCtx = sourceAspect.__ctx or { };
        currentCtx = rootCtx // aspectCtx;
        depth = state.transitionDepth or 0;
        intoResult = param.intoFn currentCtx;
        transitions = flattenInto intoResult [ ];
        targetClass = state.class or "nixos";
      in
      if depth >= maxTransitionDepth then
        throw "den: transition depth exceeded ${toString maxTransitionDepth} — likely a cycle in den.policies (${sourceAspect.name or "?"})"
      else
        {
          resume = builtins.foldl' (
            acc: transition:
            fx.bind acc (results: resolveTransition targetClass sourceAspect currentCtx results transition)
          ) (fx.pure [ ]) transitions;
          state = state // {
            transitionDepth = depth + 1;
          };
        };
  };

in
{
  inherit transitionHandler;
}
