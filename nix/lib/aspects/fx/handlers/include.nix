# Handles: emit-include
# Sends: check-constraint, resolve-complete, get-path-set
{
  lib,
  den,
  ...
}:
let
  fx = den.lib.fx;
  identity = den.lib.aspects.fx.identity;
  inherit (den.lib.aspects.fx.aspect) aspectToEffect emitIncludes;
  inherit (den.lib.aspects) isSubmoduleFn isMeaningfulName;

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

  wrapFunctorChild =
    child:
    let
      innerFn = child.__functor child;
      innerArgs = if builtins.isFunction innerFn then builtins.functionArgs innerFn else { };
    in
    if builtins.isFunction innerFn && isSubmoduleFn innerFn then
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
      };

  wrapBareFn =
    child:
    if isSubmoduleFn child then
      normalizeModuleFn child
    else
      {
        name = child.name or "<anon>";
        meta = child.meta or { };
        __fn = child;
        __args = lib.functionArgs child;
      };

  # lib.isFunction is true for both raw lambdas and functor attrsets,
  # so the first branch re-dispatches to wrapFunctorChild vs wrapBareFn.
  wrapChild =
    child:
    if lib.isFunction child then
      if builtins.isAttrs child && child ? name && child ? includes && builtins.isList child.includes then
        child
      else if builtins.isAttrs child then
        wrapFunctorChild child
      else
        wrapBareFn child
    else
      child;

  tombstoneAll =
    aspects:
    builtins.foldl' (
      acc: aspect:
      fx.bind acc (
        results:
        let
          tombstone = identity.tombstone aspect { guardFailed = true; };
        in
        fx.bind (fx.send "resolve-complete" tombstone) (_: fx.pure (results ++ [ tombstone ]))
      )
    ) (fx.pure [ ]) aspects;

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

  excludeChild =
    child: owner:
    let
      tombstone = identity.tombstone child { excludedFrom = owner; };
    in
    fx.bind (fx.send "resolve-complete" tombstone) (_: fx.pure [ tombstone ]);

  substituteChild =
    child: decision:
    let
      tombstone = identity.tombstone child {
        excludedFrom = decision.owner;
        replacedBy = decision.replacement.name or "<anon>";
      };
    in
    fx.bind (fx.send "resolve-complete" tombstone) (
      _:
      fx.bind (aspectToEffect decision.replacement) (
        resolved:
        fx.pure [
          tombstone
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
    child: decision:
    let
      # Tag the child with the constraint owner so the tracer can name
      # anonymous entries after their constraint source.
      owner = decision.owner or null;
      taggedChild =
        if owner != null then
          child
          // {
            meta = (child.meta or { }) // {
              constraintOwner = owner;
            };
          }
        else
          child;
      childArgs = taggedChild.__args or { };
      childScopeHandlers = taggedChild.__scopeHandlers or { };
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
        keysToProbe = builtins.filter (k: !(childScopeHandlers ? ${k})) requiredKeys;
        probeArgs =
          keys:
          if keys == [ ] then
            fx.pure true
          else
            let
              key = builtins.head keys;
              rest = builtins.tail keys;
            in
            fx.bind (fx.effects.hasHandler key) (
              isAvailable: if isAvailable then probeArgs rest else fx.pure false
            );
      in
      fx.bind (probeArgs keysToProbe) (
        allAvailable:
        if allAvailable then
          fx.bind (aspectToEffect taggedChild) (resolved: fx.pure [ resolved ])
        else
          # Emit a resolve-complete for the deferred child so it appears in traces,
          # then defer-include it for later resolution when context widens.
          let
            stub = {
              name = taggedChild.name or "<anon>";
              meta = (taggedChild.meta or { }) // {
                deferred = true;
              };
              includes = [ ];
            };
          in
          fx.bind (fx.send "resolve-complete" stub) (
            _:
            fx.bind (fx.send "defer-include" {
              inherit child requiredKeys;
              requiredArgs = keysToProbe;
            }) (_: fx.pure [ ])
          )
      )
    else
      fx.bind (aspectToEffect taggedChild) (resolved: fx.pure [ resolved ]);

  nameAnon =
    state: idx: ctxId:
    let
      chain = (state.includesChain or (_: [ ])) null;
      parent = if chain == [ ] then "<root>" else lib.last chain;
      suffix = if ctxId != null then "/${ctxId}" else "";
    in
    "${parent}/<anon>:${toString idx}${suffix}";

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
        withScope =
          wrapped
          // lib.optionalAttrs (parentScopeHandlers != null && !(wrapped ? __scopeHandlers)) {
            __scopeHandlers = parentScopeHandlers;
          }
          // lib.optionalAttrs (parentCtxId != null && !(wrapped ? __ctxId)) { __ctxId = parentCtxId; };
        child =
          if idx != null && !(isMeaningfulName (withScope.name or "<anon>")) then
            withScope // { name = nameAnon state idx (withScope.__ctxId or null); }
          else
            withScope;
        childIdentity = identity.pathKey (identity.aspectPath child);
        isConditional = builtins.isAttrs child && child ? meta && child.meta ? guard;
        isForward =
          builtins.isAttrs child && child ? meta && builtins.isAttrs child.meta && child.meta ? __forward;
      in
      {
        resume =
          if isForward then
            fx.bind (fx.send "emit-forward" child.meta.__forward) (_: fx.pure [ ])
          else if isConditional then
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
                  keepChild child decision
              );
        inherit state;
      };
  };

in
{
  inherit includeHandler;
}
