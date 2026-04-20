# Standalone emit-include handler — owns recursion via aspectToEffect.
# Handles: emit-include
# Sends: check-constraint, resolve-complete, get-path-set (via resolveConditional)
# State reads: (none directly — delegates to other handlers via effects)
{
  lib,
  den,
  ...
}:
let
  fx = den.lib.fx;
  identity = den.lib.aspects.fx.identity;
  inherit (den.lib.aspects.fx.aspect) aspectToEffect emitIncludes;

  # Normalize a NixOS module function ({ config, lib, ... }: ...) into an aspect
  # attrset by running it through the type system's merge. This extracts class keys
  # (nixos, homeManager, etc.) from the module's return value.
  # Coupling note: this is the only handler-layer reference to den.lib.aspects.types.
  normalizeModuleFn =
    child:
    den.lib.aspects.types.aspectType.merge
      [ (child.name or "<deferred>") ]
      [
        {
          file = "<deferred>";
          value = child;
        }
      ];

  # Wrap bare function includes in an aspect envelope.
  wrapChild =
    child:
    if lib.isFunction child then
      (
        # For attrset-with-functor children, extract the actual inner function
        # to get the real args for bind.fn resolution. This bypasses stale
        # __functionArgs on the attrset and gives aspectToEffect the correct
        # isParametric decision.
        if builtins.isAttrs child then
          let
            innerFn = child.__functor child;
            # innerFn may be a function (parametric) or a value (factory functor).
            innerArgs = if builtins.isFunction innerFn then builtins.functionArgs innerFn else { };
            # NixOS module functions are deferred modules, not parametric aspects.
            # Heuristic: any function accepting ONLY module-system args (lib, config,
            # options) is treated as a module. Functions with extra args (host, user)
            # are parametric. Edge case: { config, ... }: is classified as module —
            # if a parametric aspect genuinely takes only { config }, wrap it in an
            # aspect envelope with explicit __functionArgs instead.
            # NixOS module functions wrapped in functors (e.g. by the type system's
            # default __functor) should be normalized, not treated as parametric.
            isModuleFn =
              builtins.isFunction innerFn
              && den.lib.canTake.upTo {
                lib = true;
                config = true;
                options = true;
              } innerFn;
          in
          if isModuleFn then
            normalizeModuleFn innerFn
          else
            child
            // {
              # Preserve original __functor for wrappers that need self (e.g. perCtx
              # reads self.__ctx). Only replace with unwrapped innerFn when the child
              # uses the default aspect functor.
              __functor =
                if child ? __functionArgs && (child.__functionArgs or { }) != { } then
                  child.__functor
                else
                  _: if builtins.isFunction innerFn then innerFn else _: innerFn;
              # Preserve explicit __functionArgs if already set (e.g. by perHost/perUser
              # wrappers). Only override with innerArgs if child has no explicit args.
              __functionArgs =
                let
                  explicit = child.__functionArgs or { };
                in
                if explicit != { } then explicit else innerArgs;
              includes = child.includes or [ ];
            }
        else
          let
            args = lib.functionArgs child;
            # NixOS module functions are deferred modules, not parametric aspects.
            # Heuristic: any function accepting ONLY module-system args (lib, config,
            # options) is treated as a module. Functions with extra args (host, user)
            # are parametric. Edge case: { config, ... }: is classified as module —
            # if a parametric aspect genuinely takes only { config }, wrap it in an
            # aspect envelope with explicit __functionArgs instead.
            isModuleFn = den.lib.canTake.upTo {
              lib = true;
              config = true;
              options = true;
            } child;
          in
          if isModuleFn then
            normalizeModuleFn child
          else
            {
              name = child.name or "<anon>";
              meta = child.meta or { };
              __functor = _: child;
              __functionArgs = args;
              includes = [ ];
            }
      )
    else
      child;

  tombstoneAll =
    aspects:
    builtins.foldl' (
      acc: a:
      fx.bind acc (
        results:
        let
          ts = identity.tombstone a { guardFailed = true; };
        in
        fx.bind (fx.send "resolve-complete" ts) (_: fx.pure (results ++ [ ts ]))
      )
    ) (fx.pure [ ]) aspects;

  # Handle includeIf guards via get-path-set.
  resolveConditional =
    condNode:
    fx.bind (fx.send "get-path-set" null) (
      pathSet:
      let
        guardCtx = {
          hasAspect = ref: pathSet ? ${identity.pathKey (identity.aspectPath ref)};
        };
        pass = condNode.meta.guard guardCtx;
      in
      if pass then
        emitIncludes {
          __parentScope = condNode.__scope or null;
          __parentScopeHandlers = condNode.__scopeHandlers or null;
          __parentCtxId = condNode.__ctxId or null;
        } condNode.meta.aspects
      else
        tombstoneAll condNode.meta.aspects
    );

  # Exclude: create tombstone and emit resolve-complete.
  excludeChild =
    child: owner:
    let
      ts = identity.tombstone child { excludedFrom = owner; };
    in
    fx.bind (fx.send "resolve-complete" ts) (_: fx.pure [ ts ]);

  # Substitute: tombstone original, resolve replacement via aspectToEffect.
  substituteChild =
    child: decision:
    let
      ts = identity.tombstone child {
        excludedFrom = decision.owner;
        replacedBy = decision.replacement.name or "<anon>";
      };
    in
    fx.bind (fx.send "resolve-complete" ts) (
      _:
      fx.bind (aspectToEffect decision.replacement) (
        resolved:
        fx.pure [
          ts
          resolved
        ]
      )
    );

  handlers = den.lib.aspects.fx.handlers;

  # Keep: resolve via aspectToEffect (which emits resolve-complete internally).
  # Context is provided by handler-closures (__scope) or root constantHandler.
  #
  # For parametric children, check if each required arg has a handler:
  # 1. Check __scopeHandlers (handler-closure's handlers) — pure Nix check
  # 2. For remaining args, use has-handler effect to query root handlers
  # Unresolvable includes are deferred (resolved at deeper context level).
  keepChild =
    child:
    let
      childArgs = child.__functionArgs or { };
      childScopeHandlers = child.__scopeHandlers or { };
      isParametric = childArgs != { } && child ? __functor;
    in
    if isParametric then
      let
        # Filter out args available in __scopeHandlers (pure check, no effects needed).
        # Remaining args are probed via has-handler against root handlers.
        unresolvedKeys = builtins.filter (k: !(childScopeHandlers ? ${k})) (builtins.attrNames childArgs);
        _t = builtins.trace "keepChild: ${child.name or "?"} args=${toString (builtins.attrNames childArgs)} scopeKeys=${toString (builtins.attrNames childScopeHandlers)} unresolved=${toString unresolvedKeys}";
        probeArgs =
          keys:
          if keys == [ ] then
            fx.pure true
          else
            let
              key = builtins.head keys;
              rest = builtins.tail keys;
            in
            fx.bind (fx.send "has-handler" key) (
              isAvailable: if isAvailable then probeArgs rest else fx.pure false
            );
      in
      _t (
        fx.bind (probeArgs unresolvedKeys) (
          allAvailable:
          let
            _t2 = builtins.trace "keepChild: ${child.name or "?"} allAvailable=${toString allAvailable}";
          in
          _t2 (
            if allAvailable then
              fx.bind (aspectToEffect child) (resolved: fx.pure [ resolved ])
            else
              # Emit a resolve-complete for the deferred child so it appears in traces,
              # then defer-include it for later resolution when context widens.
              let
                stub = {
                  name = child.name or "<anon>";
                  meta = (child.meta or { }) // {
                    deferred = true;
                  };
                  includes = [ ];
                };
              in
              fx.bind (fx.send "resolve-complete" stub) (
                _:
                fx.bind (fx.send "defer-include" {
                  inherit child;
                  requiredArgs = unresolvedKeys;
                }) (_: fx.pure [ ])
              )
          )
        )
      )
    else
      fx.bind (aspectToEffect child) (resolved: fx.pure [ resolved ]);

  # Derive a stable name for anonymous aspects from parent chain + index.
  nameAnon =
    state: idx: ctxId:
    let
      chain = state.includesChain or [ ];
      parent = if chain == [ ] then "<root>" else lib.last chain;
      suffix = if ctxId != null then "/${ctxId}" else "";
    in
    "${parent}/<anon>:${toString idx}${suffix}";

  isMeaningfulName =
    name: name != "<anon>" && name != "<function body>" && !(lib.hasPrefix "[definition " name);

  # The handler. param is { child, idx, __parentScope? } from emitIncludes.
  includeHandler = {
    "emit-include" =
      { param, state }:
      let
        rawChild = param.child or param;
        idx = param.idx or null;
        parentScope = param.__parentScope or null;
        wrapped = wrapChild rawChild;
        parentCtxId = param.__parentCtxId or null;
        parentScopeHandlers = param.__parentScopeHandlers or null;
        # Propagate parent's __scope (handler-closure) and __ctxId to child.
        withScope =
          wrapped
          // lib.optionalAttrs (parentScope != null && !(wrapped ? __scope)) { __scope = parentScope; }
          // lib.optionalAttrs (parentScopeHandlers != null && !(wrapped ? __scopeHandlers)) {
            __scopeHandlers = parentScopeHandlers;
          }
          // lib.optionalAttrs (parentCtxId != null && !(wrapped ? __ctxId)) { __ctxId = parentCtxId; };
        # Replace anonymous names with parent+index derived identity.
        child =
          if idx != null && !(isMeaningfulName (withScope.name or "<anon>")) then
            withScope // { name = nameAnon state idx (withScope.__ctxId or null); }
          else
            withScope;
        _ti = builtins.trace "includeHandler: name=${child.name or "?"} scope=${toString (child ? __scope)} isParametric=${
          toString ((child.__functionArgs or { }) != { } && child ? __functor)
        }";
        childIdentity = identity.pathKey (identity.aspectPath child);
        isConditional = builtins.isAttrs child && child ? meta && child.meta ? guard;
      in
      _ti {
        resume =
          if isConditional then
            resolveConditional child
          else
            fx.bind
              (fx.send "check-constraint" {
                identity = childIdentity;
                aspect = child;
              })
              (
                decision:
                if decision.action == "exclude" then
                  excludeChild child decision.owner
                else if decision.action == "substitute" then
                  substituteChild child decision
                else
                  keepChild child
              );
        inherit state;
      };
  };

in
{
  inherit includeHandler wrapChild;
}
