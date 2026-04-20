{
  lib,
  den,
  ...
}:
let
  fx = den.lib.fx;
  identity = den.lib.aspects.fx.identity;
  inherit (den.lib.aspects.fx.handlers) constantHandler;

  structuralKeys = [
    "name"
    "description"
    "meta"
    "includes"
    "provides"
    "into"
    "__functor"
    "__functionArgs"
    "__ctx"
    "__scope"
    "__scopeHandlers"
    "__ctxId"
    "__parametricResolved"
    "__parentScope"
    "_module"
  ];

  # Emit emit-class for each non-structural attr on the aspect.
  emitClasses =
    aspect: classKeys: nodeIdentity:
    fx.seq (
      map (
        k:
        fx.send "emit-class" {
          class = k;
          identity = nodeIdentity;
          module = aspect.${k};
          contextDependent = aspect.__parametricResolved or false;
        }
      ) classKeys
    );

  # Register constraints from meta.handleWith and meta.excludes.
  registerConstraints =
    aspect:
    let
      rawHandleWith = aspect.meta.handleWith or null;
      rawExcludes = aspect.meta.excludes or [ ];
      handleWithList =
        if rawHandleWith == null then
          [ ]
        else if builtins.isList rawHandleWith then
          rawHandleWith
        else if builtins.isAttrs rawHandleWith then
          [ rawHandleWith ]
        else
          [ ];
      excludeList = map (ref: {
        type = "exclude";
        scope = "subtree";
        identity = identity.pathKey (identity.aspectPath ref);
      }) rawExcludes;
      allConstraints = handleWithList ++ excludeList;
      owner = aspect.name or "<anon>";
    in
    fx.seq (map (c: fx.send "register-constraint" (c // { inherit owner; })) allConstraints);

  # Fold includes through emit-include effects, tagging each with its
  # positional index and parent __scope (handler-closure) so the handler
  # can derive stable identities and propagate context to children.
  emitIncludes =
    {
      __parentScope ? null,
      __parentScopeHandlers ? null,
      __parentCtxId ? null,
    }:
    incs:
    let
      len = builtins.length incs;
      go =
        idx: acc:
        if idx >= len then
          acc
        else
          go (idx + 1) (
            fx.bind acc (
              results:
              fx.bind (fx.send "emit-include" (
                {
                  child = builtins.elemAt incs idx;
                  inherit idx;
                }
                // lib.optionalAttrs (__parentScope != null) { inherit __parentScope; }
                // lib.optionalAttrs (__parentScopeHandlers != null) { inherit __parentScopeHandlers; }
                // lib.optionalAttrs (__parentCtxId != null) { inherit __parentCtxId; }
              )) (childResults: fx.pure (results ++ childResults))
            )
          );
    in
    go 0 (fx.pure [ ]);

  # Emit into-transition effects for each key in aspect.into.
  # into is a function ctx → attrset. We pass the unevaluated function
  # to the handler which evaluates it with the current context.
  emitTransitions =
    aspect:
    let
      # into can be on the aspect directly (non-ctx aspects with into option)
      # or in meta.into (ctxApply stores it there to survive freeform deferredModule).
      intoFn = aspect.meta.into or aspect.into or null;
    in
    if intoFn != null && lib.isFunction intoFn then
      fx.send "into-transition" {
        inherit intoFn;
        self = aspect;
      }
    else
      fx.pure [ ];

  # Self-provide: if aspect.provides.${aspect.name} exists, emit it as an include.
  # The provider function's actual args are extracted so bind.fn can resolve
  # them through effects (e.g. { host } is resolved via constantHandler).
  # Propagates __scope (handler-closure) so the provider resolves in the right context.
  emitSelfProvide =
    aspect:
    let
      name = aspect.name or "<anon>";
      provides = aspect.provides or { };
      providerVal = provides.${name};
      scopeHandlers = aspect.__scopeHandlers or null;
      scopeFn = if scopeHandlers != null then fx.effects.scope.stateful scopeHandlers else null;
      # Entry-point ctx for positional-arg providers only.
      ctx = aspect.__ctx or { };
      # Extract real function args for bind.fn resolution.
      innerFn =
        if builtins.isAttrs providerVal && providerVal ? __functor then
          providerVal.__functor providerVal
        else
          providerVal;
      providerArgs = if lib.isFunction innerFn then lib.functionArgs innerFn else { };
    in
    if provides ? ${name} then
      let
        _t = builtins.trace "emitSelfProvide: ${name} scope=${
          if scopeFn != null then "yes" else "no"
        } providerArgs=${toString (builtins.attrNames providerArgs)}";
        # Positional-arg providers (_: { funny... }) can't be resolved via
        # bind.fn (no named args). Call them directly with ctx — ctx comes
        # from entry-point __ctx (ctxApply), not from __scope.
        isPositionalFn = lib.isFunction innerFn && providerArgs == { };
        providerMeta = {
          provider = (aspect.meta.provider or [ ]) ++ [ name ];
          selfProvide = true;
        };
        include =
          if isPositionalFn then
            let
              resolved = innerFn ctx;
              resolvedArgs = if lib.isFunction resolved then lib.functionArgs resolved else { };
            in
            if lib.isFunction resolved && !builtins.isAttrs resolved then
              {
                inherit name;
                meta = providerMeta;
                __functor = _: resolved;
                __functionArgs = resolvedArgs;
                includes = [ ];
              }
              // lib.optionalAttrs (scopeFn != null) { __parentScope = scopeFn; }
              // lib.optionalAttrs (scopeHandlers != null) { __parentScopeHandlers = scopeHandlers; }
              // lib.optionalAttrs (aspect ? __ctxId) { __parentCtxId = aspect.__ctxId; }
            else
              (if builtins.isAttrs resolved then resolved else { })
              // {
                inherit name;
                meta = providerMeta;
                includes = (if builtins.isAttrs resolved then resolved.includes or [ ] else [ ]);
              }
              // lib.optionalAttrs (aspect ? __ctxId) { __ctxId = aspect.__ctxId; }
          else
            {
              inherit name;
              meta = providerMeta;
              __functor = _: if lib.isFunction innerFn then innerFn else _: providerVal;
              __functionArgs = providerArgs;
              includes = [ ];
            }
            // lib.optionalAttrs (scopeFn != null) { __parentScope = scopeFn; }
            // lib.optionalAttrs (scopeHandlers != null) { __parentScopeHandlers = scopeHandlers; }
            // lib.optionalAttrs (aspect ? __ctxId) { __parentCtxId = aspect.__ctxId; };
      in
      _t (fx.send "emit-include" include)
    else
      fx.pure [ ];

  # Wrap a computation in chain-push/chain-pop if the node is meaningful.
  chainWrap =
    nodeIdentity: isMeaningful: comp:
    if isMeaningful then
      fx.bind (fx.send "chain-push" { identity = nodeIdentity; }) (
        _: fx.bind comp (result: fx.bind (fx.send "chain-pop" null) (_: fx.pure result))
      )
    else
      comp;

  # Resolve children, assemble the result, and emit resolve-complete.
  # Propagates __scopeHandlers to children via emitIncludes.
  resolveChildren =
    aspect:
    { isMeaningful, nodeIdentity }:
    let
      scopeHandlers = aspect.__scopeHandlers or null;
      scopeFn = if scopeHandlers != null then fx.effects.scope.stateful scopeHandlers else null;
      ctxId = aspect.__ctxId or null;
      childResolution = fx.bind (emitSelfProvide aspect) (
        selfProvResults:
        fx.bind (emitTransitions aspect) (
          transitionResults:
          fx.bind (emitIncludes {
            __parentScope = scopeFn;
            __parentScopeHandlers = scopeHandlers;
            __parentCtxId = ctxId;
          } (aspect.includes or [ ])) (children: fx.pure (selfProvResults ++ transitionResults ++ children))
        )
      );
    in
    fx.bind (chainWrap nodeIdentity isMeaningful childResolution) (
      allChildren:
      let
        resolved = aspect // {
          includes = allChildren;
        };
      in
      fx.bind (fx.send "resolve-complete" resolved) (_: fx.pure resolved)
    );

  # Compile a static (non-functor) aspect into an effectful computation.
  compileStatic =
    aspect:
    let
      nodeIdentity = identity.pathKey (identity.aspectPath aspect);
      classKeys = builtins.filter (k: !(builtins.elem k structuralKeys)) (builtins.attrNames aspect);
      _t = builtins.trace "compileStatic: name=${aspect.name or "?"} identity=${nodeIdentity} classKeys=${toString classKeys} allKeys=${toString (builtins.attrNames aspect)}";
      rawName = aspect.name or "<anon>";
      isMeaningful =
        rawName != "<anon>" && rawName != "<function body>" && !(lib.hasPrefix "[definition " rawName);
    in
    _t (
      fx.bind (fx.seq [
        (emitClasses aspect classKeys nodeIdentity)
        (registerConstraints aspect)
      ]) (_: resolveChildren aspect { inherit isMeaningful nodeIdentity; })
    );

  # The aspect compiler.
  #
  # When an aspect has __ctx (set by transition handler or propagated from
  # parent), bind.fn is scoped with constantHandler __ctx so context args
  # (host, user, etc.) resolve correctly. The scope is minimal — only around
  # the bind.fn call — so emit-class, emit-include, constraints, and chain
  # effects all reach root handlers with shared state.
  #
  # Two cases:
  # 1. __functionArgs has named args → parametric child.
  #    Resolve args via bind.fn (scoped if __ctx present), compile the result.
  # 2. Otherwise → static. Strip __functor/__functionArgs,
  #    compile the attrset directly.
  aspectToEffect =
    aspect:
    let
      userArgs = aspect.__functionArgs or { };
      isParametric = userArgs != { } && aspect ? __functor;
      scopeHandlers = aspect.__scopeHandlers or null;
      scopeFn = if scopeHandlers != null then fx.effects.scope.stateful scopeHandlers else null;
    in
    if isParametric then
      let
        fn = aspect.__functor aspect;
        _t = builtins.trace "aspectToEffect: name=${aspect.name or "?"} parametric args=${toString (builtins.attrNames userArgs)} scope=${
          if scopeFn != null then "yes" else "no"
        }";
        # Derive scope from __scopeHandlers at point of use.
        resolveFn = if scopeFn != null then scopeFn (fx.bind.fn { } fn) else fx.bind.fn { } fn;
      in
      _t (
        fx.bind resolveFn (
          resolved:
          let
            _t2 = builtins.trace "aspectToEffect: resolved name=${aspect.name or "?"} type=${builtins.typeOf resolved} isAttrs=${toString (builtins.isAttrs resolved)} keys=${
              toString (if builtins.isAttrs resolved then builtins.attrNames resolved else [ ])
            }";
          in
          _t2 (
            let
              base = {
                inherit (aspect) name;
                meta = (aspect.meta or { }) // (if builtins.isAttrs resolved then resolved.meta or { } else { });
              }
              // lib.optionalAttrs (aspect ? into) { inherit (aspect) into; }
              // lib.optionalAttrs (aspect ? provides) { inherit (aspect) provides; };
              # If resolved is still a function (curried provider), wrap it
              # as another parametric level for the next bind.fn pass.
              # Exception: submodule functions ({ config, lib, ... }: ...) are
              # NixOS modules, not parametric — merge them through the type system.
              isResolvedSubmoduleFn =
                lib.isFunction resolved
                && !builtins.isAttrs resolved
                && den.lib.canTake.upTo {
                  inherit lib;
                  config = true;
                  options = true;
                } resolved;
              # Required args from the original parametric function — used for
              # exact-match context guarding on the resolved child.
              requiredArgs = builtins.filter (n: !userArgs.${n}) (builtins.attrNames userArgs);
              # Forward-wrap: when a parametric fn resolves to a static attrset,
              # annotate with meta.contextGuard so keepChild enforces exact context
              # match when the child later appears as an include.
              # IMPORTANT: strip __functor/__functionArgs so aspectToEffect routes
              # to compileStatic — otherwise it re-enters the parametric path and
              # infinite-loops. The guard.aspect holds the original child for
              # re-emission by keepChild at the right context level.
              forwardWrap =
                child:
                if requiredArgs != [ ] then
                  builtins.removeAttrs child [
                    "__functor"
                    "__functionArgs"
                  ]
                  // {
                    meta = (child.meta or { }) // {
                      contextGuard = {
                        type = "exactly";
                        keys = builtins.sort builtins.lessThan requiredArgs;
                        aspect = child;
                      };
                    };
                  }
                else
                  child;
              next =
                if lib.isFunction resolved && !builtins.isAttrs resolved then
                  if isResolvedSubmoduleFn then
                    # Submodule fn: merge through aspect type to get proper attrset
                    let
                      merged = den.lib.aspects.types.aspectType.merge (aspect.meta.loc or [ (aspect.name or "<anon>") ]) [
                        {
                          file = aspect.meta.file or "<parametric>";
                          value = resolved;
                        }
                      ];
                    in
                    base // builtins.removeAttrs merged [ "meta" ]
                  else
                    base
                    // {
                      __functor = _: resolved;
                      __functionArgs = lib.functionArgs resolved;
                      includes = [ ];
                    }
                else
                  forwardWrap (base // builtins.removeAttrs resolved [ "meta" ]);
              # Propagate __scope, __ctx and __ctxId so children inherit context.
              # Compose __scope with resolved result's __ctx (from fixedTo/expands)
              # if present. The resolved ctx becomes additional scope handlers.
              resolvedCtx = if builtins.isAttrs resolved then resolved.__ctx or { } else { };
              resolvedCtxHandlers = if resolvedCtx != { } then constantHandler resolvedCtx else null;
              resolvedScope =
                if resolvedCtx != { } && scopeFn != null then
                  comp: scopeFn (fx.effects.scope.stateful resolvedCtxHandlers comp)
                else if resolvedCtx != { } then
                  fx.effects.scope.stateful resolvedCtxHandlers
                else
                  scopeFn;
              scopeHandlers = aspect.__scopeHandlers or null;
              resolvedScopeHandlers =
                if resolvedCtxHandlers != null && scopeHandlers != null then
                  scopeHandlers // resolvedCtxHandlers
                else if resolvedCtxHandlers != null then
                  resolvedCtxHandlers
                else
                  scopeHandlers;
              tagged =
                next
                // lib.optionalAttrs (resolvedScope != null) { __scope = resolvedScope; }
                // lib.optionalAttrs (resolvedScopeHandlers != null) { __scopeHandlers = resolvedScopeHandlers; }
                // lib.optionalAttrs (aspect ? __ctxId) { inherit (aspect) __ctxId; }
                // {
                  __parametricResolved = true;
                };
            in
            aspectToEffect tagged
          )
        )
      )
    else
      compileStatic (
        builtins.removeAttrs aspect [
          "__functor"
          "__functionArgs"
        ]
      );

in
{
  inherit
    aspectToEffect
    emitIncludes
    emitTransitions
    emitSelfProvide
    ;
}
