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
    "__ctxId"
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
  # positional index and parent __ctx so the handler can derive stable
  # identities and propagate context to children.
  emitIncludes =
    {
      parentCtx,
      parentCtxId ? null,
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
                  inherit idx parentCtx;
                }
                // lib.optionalAttrs (parentCtxId != null) { inherit parentCtxId; }
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
    if aspect ? into then
      fx.send "into-transition" {
        intoFn = aspect.into;
        self = aspect;
      }
    else
      fx.pure [ ];

  # Self-provide: if aspect.provides.${aspect.name} exists, emit it as an include.
  # The provider function's actual args are extracted so bind.fn can resolve
  # them through effects (e.g. { host } is resolved via constantHandler).
  # Propagates __ctx so the provider can resolve in the right context.
  emitSelfProvide =
    aspect:
    let
      name = aspect.name or "<anon>";
      provides = aspect.provides or { };
      providerVal = provides.${name};
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
        _t = builtins.trace "emitSelfProvide: ${name} parentCtx=${toString (builtins.attrNames ctx)} providerArgs=${toString (builtins.attrNames providerArgs)}";
      in
      _t (
        fx.send "emit-include" (
          {
            inherit name;
            parentCtx = ctx;
            meta = {
              provider = (aspect.meta.provider or [ ]) ++ [ name ];
              selfProvide = true;
            };
            __functor = _: if lib.isFunction innerFn then innerFn else _: providerVal;
            __functionArgs = providerArgs;
            includes = [ ];
          }
          // lib.optionalAttrs (aspect ? __ctxId) { parentCtxId = aspect.__ctxId; }
        )
      )
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
  # Propagates __ctx to children via emitIncludes parentCtx parameter.
  resolveChildren =
    aspect:
    { isMeaningful, nodeIdentity }:
    let
      ctx = aspect.__ctx or { };
      ctxId = aspect.__ctxId or null;
      childResolution = fx.bind (emitSelfProvide aspect) (
        selfProvResults:
        fx.bind (emitTransitions aspect) (
          transitionResults:
          fx.bind (emitIncludes {
            parentCtx = ctx;
            parentCtxId = ctxId;
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
      ctx = aspect.__ctx or { };
    in
    if isParametric then
      let
        fn = aspect.__functor aspect;
        _t = builtins.trace "aspectToEffect: name=${aspect.name or "?"} parametric args=${toString (builtins.attrNames userArgs)} __ctx=${toString (builtins.attrNames ctx)}";
        # If __ctx is present, scope bind.fn with constantHandler so context
        # args (host, user) resolve from __ctx. Other args (class, aspect-chain)
        # rotate to root constantHandler. Scope is ONLY around bind.fn —
        # the resume is a plain value, no state isolation.
        resolveFn =
          if ctx != { } then
            fx.effects.scope.run {
              handlers = constantHandler ctx;
            } (fx.bind.fn { } fn)
          else
            fx.bind.fn { } fn;
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
              # add a __functor that enforces exact context match. This makes
              # { host }: expr only fire at host level (not user level where
              # ctx also has user). Also propagates identity (name) from the
              # original aspect so the child isn't anonymous for constraints.
              forwardWrap =
                child:
                if requiredArgs != [ ] then
                  child
                  // {
                    __functor =
                      _: newCtx:
                      let
                        ctxKeys = builtins.sort builtins.lessThan (builtins.attrNames newCtx);
                        reqKeys = builtins.sort builtins.lessThan requiredArgs;
                      in
                      if ctxKeys == reqKeys then child // { __ctx = newCtx; } else { };
                    # NOTE: no __functionArgs here — that would make aspectToEffect
                    # treat this as parametric again, causing infinite recursion.
                    # The __functor is only used when the child is later called
                    # via ctxApply or transition, not during pipeline resolution.
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
              # Propagate __ctx and __ctxId so children inherit context and identity.
              # Merge parent ctx WITH resolved result's __ctx (from fixedTo/expands)
              # so pinned values aren't overwritten by parent context.
              resolvedCtx = if builtins.isAttrs resolved then resolved.__ctx or { } else { };
              tagged =
                next
                // lib.optionalAttrs (ctx != { } || resolvedCtx != { }) { __ctx = ctx // resolvedCtx; }
                // lib.optionalAttrs (aspect ? __ctxId) { inherit (aspect) __ctxId; };
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
