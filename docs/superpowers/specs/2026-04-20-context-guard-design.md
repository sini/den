# Pipeline-native context guards

## Problem

Context-level guards (`perHost`, `perUser`, `take.exactly`, `forwardWrap`) use
`__functor` to check whether an aspect should resolve at a given context level.
This couples guard logic to functor mechanics and requires `__ctx` data-stamping
by the default functor (`self: ctx: self // { __ctx = ctx; }`).

The `__ctx` attribute serves two roles today:

1. **Propagation** (parent -> child) — already replaced by `__scopeHandlers`
2. **Self-identification** (what context was I resolved with) — read by guards via `self.__ctx`

Role 2 can be eliminated by moving guard checks into the pipeline handler system,
where `__scopeHandlers` keys already represent the current context level.

Additionally, aspects carry both `__scope` (an opaque pre-applied
`scope.stateful` closure) and `__scopeHandlers` (the inspectable handler
attrset). `__scope` is redundant — it can be derived from `__scopeHandlers`
at point of use via `fx.effects.scope.stateful handlers`. Consolidating to
`__scopeHandlers` alone gives a single inspectable source of truth.

## Design

### Guard metadata

Aspects annotate themselves with `meta.contextGuard` instead of implementing
guard logic in `__functor`:

```nix
meta.contextGuard = {
  type = "exactly";       # | "atLeast" | "upTo"
  keys = [ "host" ];      # sorted required context keys
  aspect = innerAspect;   # what to resolve on match (may be function or attrset)
};
```

Combined with `__functionArgs` which signals `keepChild` what minimum keys are
needed before the guard can even be evaluated.

### keepChild logic (include.nix)

Current gate: `isParametric = childArgs != {} && child ? __functor`.

New: also handle children with `meta.contextGuard`:

```
guard = child.meta.contextGuard or null

if guard != null:
  scopeKeys = sort(attrNames childScopeHandlers)

  "exactly":
    scopeKeys == guard.keys                        -> match: emitIncludes [guard.aspect]
    all guard.keys in scopeKeys (but has extras)   -> drop:  fx.pure []  (with trace)
    else                                           -> defer: defer-include

  "atLeast":
    all guard.keys in scopeKeys     -> match
    else                            -> defer

  "upTo":
    any guard.key in scopeKeys      -> match
    else                            -> defer
```

On match, re-emit `guard.aspect` via `emitIncludes` with propagated scope/ctxId.
This follows the `resolveConditional` pattern: guard checks condition, inner
aspects re-enter the full handler chain (check-constraint, keepChild, etc.).

On drop (exactly guard with extra keys), emit a trace line for debugging and
return `fx.pure []`. The aspect is excluded — it belongs to a different
context level.

### Consumer changes

#### perCtx (perHost-perUser.nix)

Before:
```nix
perCtx = requiredKeys: aspect: {
  includes = [{
    __functor = self: _:
      let ctx = self.__ctx or {};
          ctxKeys = sort (attrNames ctx);
      in if ctxKeys == reqKeysSorted
         then if isParametric then aspect ctx else aspect
         else {};
    __functionArgs = { ${minKey} = false; };
    includes = [];
  }];
};
```

After:
```nix
perCtx = requiredKeys: aspect: {
  includes = [{
    __functionArgs = { ${minKey} = false; };
    meta.contextGuard = {
      type = "exactly";
      keys = reqKeysSorted;
      inherit aspect;
    };
    name = "<guard:${lib.concatStringsSep "," reqKeysSorted}>";
    includes = [];
  }];
};
```

No `__functor`. The pipeline handles the guard check and resolution.

#### take.nix

Before:
```nix
guard = pred: fn: {
  __functor = self: _:
    let ctx = self.__ctx or {};
    in if pred ctx fn then fn ctx else {};
  __functionArgs = { ${minKey} = false; };
  includes = [];
};
```

After:
```nix
take.exactly = fn:
  let
    args = lib.functionArgs fn;
    requiredKeys = builtins.filter (k: !args.${k}) (builtins.attrNames args);
    sortedKeys = builtins.sort builtins.lessThan requiredKeys;
    minKey = builtins.head sortedKeys;
  in {
    __functionArgs = { ${minKey} = false; };
    meta.contextGuard = {
      type = "exactly";
      keys = sortedKeys;
      aspect = fn;
    };
    includes = [];
  };
```

`take.atLeast` and `take.upTo` use `type = "atLeast"` / `type = "upTo"`.

The generic `take.__functor` (custom predicate form) is deprecated.

#### forwardWrap (aspect.nix)

Before:
```nix
forwardWrap = child:
  if requiredArgs != [] then
    child // {
      __functor = _: newCtx:
        let ctxKeys = sort (attrNames newCtx);
            reqKeys = sort requiredArgs;
        in if ctxKeys == reqKeys then child // { __ctx = newCtx; } else {};
    }
  else child;
```

After:
```nix
forwardWrap = child:
  if requiredArgs != [] then
    child // {
      __functionArgs = lib.genAttrs requiredArgs (_: false);
      meta = (child.meta or {}) // {
        contextGuard = {
          type = "exactly";
          keys = builtins.sort builtins.lessThan requiredArgs;
          aspect = child;
        };
      };
    }
  else child;
```

No `__functor`. The `__functionArgs` makes `keepChild` defer until context is
available. The `meta.contextGuard` makes it exact-match.

### Default functor (types.nix)

Changes to identity:

```nix
default = self: _: self;
```

No `__ctx` stamping. Context flows through `__scopeHandlers`.

### __scope removal — single source of truth

`__scope` is `scope.stateful __scopeHandlers` pre-applied. Every site that
reads `__scope` can derive it from `__scopeHandlers` at point of use.

**Producers (stop creating `__scope`):**

- `ctx-apply.nix`: only stamp `__scopeHandlers = constantHandler ctx`
- `transition.nix`: only stamp `__scopeHandlers` on target aspects
- `aspectToEffect` tagged block: only propagate `__scopeHandlers`
- `parametric.nix` shims: only stamp `__scopeHandlers`

**Consumers (derive scope from handlers):**

- `aspectToEffect` (aspect.nix:274-284): wrap `bind.fn` in scope at point of use:
  ```nix
  scopeHandlers = aspect.__scopeHandlers or null;
  resolveFn =
    if scopeHandlers != null
    then fx.effects.scope.stateful scopeHandlers (fx.bind.fn {} fn)
    else fx.bind.fn {} fn;
  ```

- `emitSelfProvide` (aspect.nix:131): same pattern for provider resolution

- `compileStatic` (aspect.nix:213): passes `__parentScopeHandlers` to
  `emitIncludes` (already does this; stop passing `__parentScope`)

- `includeHandler` (include.nix:262-269): propagate `parentScopeHandlers` only.
  Stop propagating `parentScope`.

- `default.nix:62`: drop `__scope` preservation during wrapping

**Structural keys:** Remove `"__scope"` from `structuralKeys` in `aspect.nix`
and `ctx-apply.nix`.

### resolvedCtx removal (aspect.nix)

The `resolvedCtx` block (lines 366-383) extracted `resolved.__ctx` from the
functor's return value and composed it into the scope chain. This served two
purposes:

1. **Default functor echo** — re-injected the resolved args into the child's
   scope. Redundant: the parent `__scopeHandlers` already provides
   these args to children.

2. **Deprecated `fixedTo`/`expands`** — stamped `__ctx` on aspects before
   pipeline entry. The extraction converted this to scope handlers.

With the identity functor, purpose 1 is gone. For purpose 2, the deprecated
shims are updated to stamp `__scopeHandlers` directly:

```nix
# parametric.nix — fixedTo shim
parametric.fixedTo.__functor = _: ctx: aspect:
  warn "fixedTo is deprecated" (
    aspect // { __scopeHandlers = constantHandler ctx; }
  );

# parametric.nix — expands shim
parametric.expands = attrs: aspect:
  let
    existingHandlers = aspect.__scopeHandlers or {};
    merged = existingHandlers // constantHandler attrs;
  in
  warn "expands is deprecated" (
    aspect // { __scopeHandlers = merged; }
  );
```

With both purposes handled, the `resolvedCtx` block is removed entirely.
Lines 366-383 simplify to passing through the parent's scope unchanged:

```nix
tagged =
  next
  // lib.optionalAttrs (scopeHandlers != null) { __scopeHandlers = scopeHandlers; }
  // lib.optionalAttrs (aspect ? __ctxId) { inherit (aspect) __ctxId; }
  // { __parametricResolved = true; };
```

### What stays

- `__ctx` on ctxApply results — seeds `state.currentCtx` for `into` functions
- `__ctx` stamps from transition handler — for entry-point seeding when results
  re-enter `fxResolveTree`
- `__scopeHandlers` propagation — the single source of truth for context

### What's removed

- `__scope` (opaque pre-applied closure) — derived from `__scopeHandlers` at use
- `__functor`-based guards in `take.nix`, `perCtx`, `forwardWrap`
- `self.__ctx` reads in guard code
- `__ctx` stamping in the default functor
- `resolvedCtx` extraction block in `aspectToEffect`
- The `__ctx` module option in `types.nix` (already removed)
- The generic `take.__functor` custom predicate form (deprecated)

## Files changed

| File | Change |
|------|--------|
| `nix/lib/aspects/fx/handlers/include.nix` | `keepChild`: guard-aware resolution via `emitIncludes` |
| `nix/lib/aspects/fx/aspect.nix` | Remove `__scope` reads, derive from `__scopeHandlers`; `forwardWrap`: metadata; remove `resolvedCtx` block |
| `nix/lib/aspects/fx/handlers/transition.nix` | Stop stamping `__scope`, only stamp `__scopeHandlers` |
| `nix/lib/ctx-apply.nix` | Stop stamping `__scope`, only stamp `__scopeHandlers` |
| `nix/lib/aspects/default.nix` | Drop `__scope` preservation during wrapping |
| `modules/context/perHost-perUser.nix` | Replace functor guard with `meta.contextGuard` |
| `nix/lib/take.nix` | Replace functor guard with `meta.contextGuard`; deprecate custom pred |
| `nix/lib/aspects/types.nix` | Default functor: `self: _: self`; remove `__scope` from structuralKeys |
| `nix/lib/parametric.nix` | Update shims to stamp `__scopeHandlers` instead of `__ctx` |
