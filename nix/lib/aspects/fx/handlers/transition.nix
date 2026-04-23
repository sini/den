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
        __ctxId = ctxId;
      };
    in
    fx.bind (aspectToEffect tagged) (
      childResult:
      # Drain deferred includes now satisfiable with the new context.
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

  # Resolve a single transition: look up target aspect, check dedup, resolve each context value.
  # Also emits cross-providers: if sourceAspect.provides.${targetKey} exists,
  # that provider is resolved in the scoped context (e.g. flake-system.provides.flake-packages).
  # Stages provide the target's identity. Policies provide nested transitions.
  buildTarget =
    transition:
    let
      stageAspect = lib.attrByPath transition.path null (den.stages or { });

      targetName = if stageAspect != null then stageAspect.name or "" else "";
      policyInto = den.lib.synthesizePolicies targetName;
    in
    if stageAspect != null && policyInto != null then
      stageAspect
      // {
        meta = (stageAspect.meta or { }) // {
          into = policyInto;
        };
      }
    else if stageAspect != null then
      stageAspect
    else
      null;

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
      mergeImports = fx.effects.state.modify (st: st // { imports = x: (st.imports x) ++ subImports; });
    in
    fx.bind mergeImports (_: fx.pure innerResults);

  resolveTransition =
    targetClass: sourceAspect: currentCtx: results: transition:
    let
      key = "${targetClass}/${lib.concatStringsSep "/" transition.path}";
      targetKey = lib.concatStringsSep "." transition.path;
      effectiveTarget = buildTarget transition;
      sourceProvides = sourceAspect.provides or { };
      crossProvider = sourceProvides.${targetKey} or null;
      emitCross = emitCrossProvider { inherit crossProvider sourceAspect targetKey; };
    in
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
      in
      builtins.foldl' (
        acc: newCtx:
        fx.bind acc (
          innerResults:
          let
            scopedCtx = currentCtx // newCtx;
            ctxNames = mkCtxId newCtx;
            ctxKey = if isFanOut then "${key}/{${ctxNames}}" else key;
            scopeHandlers = constantHandler scopedCtx;
            updateCtx = fx.effects.state.modify (st: st // { currentCtx = _: scopedCtx; });
            withTarget =
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
        # and policy guards like (ctx ? user) fail.
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
