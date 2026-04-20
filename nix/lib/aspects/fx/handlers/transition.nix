# into-transition handler — processes context transitions via handler-closures.
# Handles: into-transition
# Sends: ctx-seen (dedup), resolve-complete (missing transition tombstone),
#        then aspectToEffect with __scope-tagged target aspects.
# Cross-providers: if source.provides.${targetKey} exists, tagged and resolved alongside.
# State reads: currentCtx
# External dependency: den.ctx (context aspect registry, looked up by transition path)
#
# Context propagation: transitions tag target aspects with __scope — a partially
# applied scope.stateful (handler-closure). aspectToEffect applies __scope around
# bind.fn so parametric args (host, user, etc.) resolve from the captured handlers.
# The closure carries context across pipeline boundaries (separate fxResolve calls).
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
  # and resolving it directly. No scope.run — context flows as data.
  resolveContextValue =
    parentCtx: targetAspect: results: newCtx:
    let
      scopedCtx = parentCtx // newCtx;
      # __ctxId differentiates fan-out contexts with the same target aspect.
      # Derives identity from entity names (v.name for attrsets) or string
      # values in newCtx. Assumes all context values are either:
      # - Entities with a .name attribute (host, user objects)
      # - Strings (like system = "x86_64-linux")
      # - Other attrsets (fallback: uses the key name, may collide if two
      #   contexts share key names but differ in non-name values)
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
      # Handler-closure: partially applied scope.stateful that captures context.
      # aspectToEffect applies this around bind.fn to resolve parametric args.
      # __scopeHandlers stored separately for state-transparent probing via scope.provide.
      scopeHandlers = constantHandler scopedCtx;
      scopeFn = fx.effects.scope.stateful scopeHandlers;
      tagged = targetAspect // {
        __scope = scopeFn;
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
                  __scope = scopeFn;
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
  resolveTransition =
    sourceAspect: currentCtx: results: transition:
    let
      key = lib.concatStringsSep "/" transition.path;
      targetKey = lib.concatStringsSep "." transition.path;
      targetAspect = lib.attrByPath transition.path null (den.ctx or { });
      sourceProvides = sourceAspect.provides or { };
      crossProvider = sourceProvides.${targetKey} or null;
      # Emit cross-provider result by tagging with __scope and resolving.
      emitCrossProvider =
        scopedCtx: scopeFn: scopeHandlers: ctxId: prevResults:
        if crossProvider != null then
          let
            # Call crossProvider with only the args it accepts, not the full
            # scopedCtx. Curried providers (e.g. { name }: { shout }: ...) take
            # the source ctx first; extra keys would cause unexpected-arg errors.
            crossProviderArgs = lib.functionArgs crossProvider;
            crossCtx =
              if crossProviderArgs != { } then builtins.intersectAttrs crossProviderArgs scopedCtx else scopedCtx;
            crossResult = crossProvider crossCtx;
            # Wrap bare functions as parametric aspects for aspectToEffect.
            wrapped =
              if lib.isFunction crossResult && !builtins.isAttrs crossResult then
                {
                  name = "${sourceAspect.name or "?"}.provides.${targetKey}";
                  meta = { };
                  __functor = _: crossResult;
                  __functionArgs = lib.functionArgs crossResult;
                  __scope = scopeFn;
                  __scopeHandlers = scopeHandlers;
                  __ctx = scopedCtx;
                  __ctxId = ctxId;
                  includes = [ ];
                }
              else
                crossResult
                // {
                  __scope = scopeFn;
                  __scopeHandlers = scopeHandlers;
                  __ctx = scopedCtx;
                  __ctxId = ctxId;
                };
          in
          fx.bind (aspectToEffect wrapped) (crossResolved: fx.pure (prevResults ++ [ crossResolved ]))
        else
          fx.pure prevResults;
    in
    if targetAspect == null && crossProvider == null then
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
      fx.bind (fx.send "ctx-seen" key) (
        { isFirst }:
        if !isFirst then
          fx.pure results
        else
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
                # Build handler-closure for this transition context.
                scopeHandlers = constantHandler scopedCtx;
                scopeFn = fx.effects.scope.stateful scopeHandlers;
                # Update state.currentCtx so nested transitions' intoFn
                # receives accumulated context.
                updateCtx = fx.effects.state.modify (st: st // { currentCtx = _: scopedCtx; });
                withTarget =
                  if targetAspect != null then
                    resolveContextValue currentCtx targetAspect innerResults newCtx
                  else
                    fx.pure innerResults;
              in
              fx.bind updateCtx (
                _:
                fx.bind withTarget (
                  targetResults: emitCrossProvider scopedCtx scopeFn scopeHandlers ctxNames targetResults
                )
              )
            )
          ) (fx.pure results) transition.contexts
      );

  transitionHandler = {
    "into-transition" =
      { param, state }:
      let
        sourceAspect = param.self;
        # currentCtx is wrapped in a thunk (_: ctx) to survive deepSeq.
        rootCtx = (state.currentCtx or (_: { })) null;
        # rootCtx feeds the into function. Nested transitions get parent
        # context from __scope handler-closures, not from data merging.
        currentCtx = rootCtx;
        intoResult = param.intoFn currentCtx;
        transitions = flattenInto intoResult [ ];
      in
      {
        resume = builtins.foldl' (
          acc: transition: fx.bind acc (results: resolveTransition sourceAspect currentCtx results transition)
        ) (fx.pure [ ]) transitions;
        inherit state;
      };
  };

in
{
  inherit transitionHandler;
}
