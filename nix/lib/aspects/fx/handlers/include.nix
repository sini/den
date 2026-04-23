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
  # lib.isFunction catches raw lambdas and real functor attrsets (ctx nodes,
  # explicit wrappers). Plain aspects (no __functor after option removal) and
  # parametric wrappers (__fn/__args, no __functor) skip to else → pass-through.
  wrapChild =
    child:
    if lib.isFunction child then
      (
        # Merged aspects have __functor (for callability) but should NOT
        # be treated as functor-based providers. Detect them by the
        # presence of declared submodule options (name + includes).
        if builtins.isAttrs child && child ? name && child ? includes && builtins.isList child.includes then
          child
        else if builtins.isAttrs child then
          let
            innerFn = child.__functor child;
            innerArgs = if builtins.isFunction innerFn then builtins.functionArgs innerFn else { };
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
              __fn =
                if child ? __args then
                  child.__fn
                else if builtins.isFunction innerFn then
                  innerFn
                else
                  _: innerFn;
              __args =
                let
                  explicit = child.__args or { };
                in
                if explicit != { } then explicit else innerArgs;
              includes = child.includes or [ ];
            }
        else
          let
            args = lib.functionArgs child;
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
              __fn = child;
              __args = args;
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
  # Context is provided by handler-closures (__scopeHandlers) or root constantHandler.
  #
  # For parametric children, check if each required arg has a handler:
  # 1. Check __scopeHandlers (handler-closure's handlers) — pure Nix check
  # 2. For remaining args, use has-handler effect to query root handlers
  # Unresolvable includes are deferred (resolved at deeper context level).
  keepChild =
    child:
    let
      childArgs = child.__args or { };
      childScopeHandlers = child.__scopeHandlers or { };
      isParametric = childArgs != { };
    in
    if isParametric then
      let
        # Only required args (value == false in __args) must have handlers.
        # Optional args (value == true) are resolved if available but don't
        # block — they're context-level guards (perHost/perUser/take.exactly).
        requiredKeys = builtins.filter (k: !childArgs.${k}) (builtins.attrNames childArgs);
        # Filter out args available in __scopeHandlers (pure check, no effects needed).
        # Remaining required args are probed via has-handler against root handlers.
        unresolvedKeys = builtins.filter (k: !(childScopeHandlers ? ${k})) requiredKeys;
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
      fx.bind (probeArgs unresolvedKeys) (
        allAvailable:
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
              inherit child requiredKeys;
              requiredArgs = unresolvedKeys;
            }) (_: fx.pure [ ])
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

  # The handler. param is { child, idx, __parentScopeHandlers? } from emitIncludes.
  includeHandler = {
    "emit-include" =
      { param, state }:
      let
        rawChild = param.child or param;
        idx = param.idx or null;
        wrapped = wrapChild rawChild;
        parentCtxId = param.__parentCtxId or null;
        parentScopeHandlers = param.__parentScopeHandlers or null;
        # Propagate parent's __scopeHandlers and __ctxId to child.
        withScope =
          wrapped
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
        childIdentity = identity.pathKey (identity.aspectPath child);
        isConditional = builtins.isAttrs child && child ? meta && child.meta ? guard;
      in
      {
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
