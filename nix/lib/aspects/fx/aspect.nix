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
    "__fn"
    "__args"
    "__functor"
    "__ctx"
    "__scopeHandlers"
    "__ctxId"
    "__parametricResolved"
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
  # positional index and parent __scopeHandlers so the handler
  # can derive stable identities and propagate context to children.
  emitIncludes =
    {
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
  # Propagates __scopeHandlers so the provider resolves in the right context.
  emitSelfProvide =
    aspect:
    let
      name = aspect.name or "<anon>";
      provides = aspect.provides or { };
      providerVal = provides.${name};
      scopeHandlers = aspect.__scopeHandlers or null;
      # Entry-point ctx for positional-arg providers only.
      ctx = aspect.__ctx or { };
      # Extract real function args for bind.fn resolution.
      # Detect __fn/__args wrappers (from take.exactly, perCtx, etc.) and
      # preserve them as-is so aspectToEffect can handle them correctly
      # (including meta.exactMatch injection, scope.provide, etc.).
      isParametricWrapper = builtins.isAttrs providerVal && providerVal ? __fn && providerVal ? __args;
      innerFn =
        if isParametricWrapper then
          providerVal.__fn
        else if builtins.isAttrs providerVal && providerVal ? __fn then
          providerVal.__fn
        else if builtins.isAttrs providerVal && lib.isFunction providerVal then
          providerVal.__functor providerVal
        else
          providerVal;
      providerArgs =
        if isParametricWrapper then
          providerVal.__args
        else if lib.isFunction innerFn then
          lib.functionArgs innerFn
        else
          { };
    in
    if provides ? ${name} then
      let
        _t = builtins.trace "emitSelfProvide: ${name} scope=${
          if scopeHandlers != null then "yes" else "no"
        } providerArgs=${toString (builtins.attrNames providerArgs)}";
        # Positional-arg providers (_: { funny... }) can't be resolved via
        # bind.fn (no named args). Call them directly with ctx — ctx comes
        # from entry-point __ctx (ctxApply), not from __scopeHandlers.
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
                __fn = resolved;
                __args = resolvedArgs;
              }
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
              meta =
                providerMeta
                // (
                  if isParametricWrapper then
                    builtins.removeAttrs (providerVal.meta or { }) [
                      "provider"
                      "selfProvide"
                    ]
                  else
                    { }
                );
              __fn = if lib.isFunction innerFn then innerFn else _: providerVal;
              __args = providerArgs;
            }
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
      ctxId = aspect.__ctxId or null;
      childResolution = fx.bind (emitSelfProvide aspect) (
        selfProvResults:
        fx.bind (emitTransitions aspect) (
          transitionResults:
          fx.bind (emitIncludes {
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
  # 1. __args has named args → parametric wrapper.
  #    Resolve args via bind.fn (scoped if __scopeHandlers present), compile the result.
  # 2. Otherwise → static. Strip __fn/__args, compile the attrset directly.
  aspectToEffect =
    aspect:
    let
      userArgs = aspect.__args or { };
      isParametric = userArgs != { };
      scopeHandlers = aspect.__scopeHandlers or null;
      scopeFn = if scopeHandlers != null then fx.effects.scope.provide scopeHandlers else null;
    in
    if isParametric then
      let
        rawFn = aspect.__fn;
        # For exactMatch wrappers (take.exactly), inject __scopeKeys so the
        # wrapper can detect extra context beyond its declared args.
        fn =
          if (aspect.meta.exactMatch or false) && scopeHandlers != null then
            args: rawFn (args // { __scopeKeys = builtins.attrNames scopeHandlers; })
          else
            rawFn;
        _t = builtins.trace "aspectToEffect: name=${aspect.name or "?"} parametric args=${toString (builtins.attrNames userArgs)} scope=${
          if scopeFn != null then "yes" else "no"
        }";
        # Use bind.fn with __args as extra attrs so optional/required args
        # are resolved via effects. For named-arg functions this merges with
        # lib.functionArgs; for positional-arg wrappers (__fn = resolvedArgs: ...)
        # it provides the full arg spec since lib.functionArgs returns {}.
        resolveFn = if scopeFn != null then scopeFn (fx.bind.fn userArgs fn) else fx.bind.fn userArgs fn;
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
              # Identity — parametric wrappers use __fn/__args, resolved
              # children don't carry spurious functor attrs.
              forwardWrap = child: child;
              next =
                if lib.isFunction resolved && !builtins.isAttrs resolved then
                  if isResolvedSubmoduleFn then
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
                      __fn = resolved;
                      __args = lib.functionArgs resolved;
                    }
                else
                  forwardWrap (base // builtins.removeAttrs resolved [ "meta" ]);
              # Propagate __scopeHandlers and __ctxId so children inherit context.
              # Merge parent's scopeHandlers with resolved value's scopeHandlers
              # (from fixedTo/expands shims that stamp __scopeHandlers on wrappers).
              parentScopeHandlers = aspect.__scopeHandlers or { };
              resolvedScopeHandlers = if builtins.isAttrs next then next.__scopeHandlers or { } else { };
              mergedScopeHandlers = parentScopeHandlers // resolvedScopeHandlers;
              tagged =
                next
                // lib.optionalAttrs (mergedScopeHandlers != { }) { __scopeHandlers = mergedScopeHandlers; }
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
          "__fn"
          "__args"
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
