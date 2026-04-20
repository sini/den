# Remove context guards — handler-based resolution makes them unnecessary

## Problem

Context-level guards (`perHost`, `perUser`, `take.exactly`, `forwardWrap`) exist
because the old manual-context-forwarding model called functions directly with a
context attrset. A function `{ host }: expr` called at user level received
`{ host, user }` — extra keys leaked through. Guards prevented firing at the
wrong level.

Under handler-based resolution, `bind.fn` compiles `{ host, user }: expr` into
chained effect requests. Each arg is resolved independently from scoped handlers.
A function asking for `{ host }` gets exactly `{ host }` — never `user`, even
if `user` is in scope. The `exactly/atLeast/upTo` distinction is meaningless.

Additionally, `__ctx` data-stamping and `__scope` closures are redundant with
`__scopeHandlers`, which is the single inspectable source of truth.

## Design

### No guard mechanism in the pipeline

The pipeline is agnostic to legacy guard patterns. No `meta.contextGuard`, no
context-key-set matching, no `exactly/atLeast/upTo` awareness. Resolution
relies entirely on:

1. `keepChild` defers until required args have handlers (`has-handler` probing)
2. `bind.fn` resolves exactly the declared args from scoped handlers
3. First context level to satisfy all args wins (natural from deferral)

### Deprecation shims at the boundary

Legacy APIs become identity wrappers with deprecation warnings. They reshape
user code to pass through the pipeline unchanged.

#### perCtx (perHost-perUser.nix)

```nix
perCtx = requiredKeys: aspect:
  lib.warn "den.lib.perCtx is deprecated — handler-based resolution makes context guards unnecessary"
    aspect;

perHost = perCtx [ "host" ];
perUser = perCtx [ "host" "user" ];
perHome = perCtx [ "home" ];
```

`perHost myAspect` → warns, returns `myAspect` unchanged. The pipeline resolves
it when `host` is available in handlers. No guard check needed.

#### take.nix

```nix
take.exactly = fn:
  lib.warn "den.lib.take.exactly is deprecated — bind.fn resolves args from handlers"
    fn;

take.atLeast = fn:
  lib.warn "den.lib.take.atLeast is deprecated — bind.fn resolves args from handlers"
    fn;

take.upTo = fn:
  lib.warn "den.lib.take.upTo is deprecated — bind.fn resolves args from handlers"
    fn;

take.__functor = _: _pred: _adapter: fn:
  lib.warn "den.lib.take custom predicate is deprecated"
    fn;
```

All forms become identity + warning. The inner function passes through as a
normal parametric aspect.

#### forwardWrap (aspect.nix)

```nix
forwardWrap = child: child;
```

Identity. Under handler-based resolution, the pipeline's deferral mechanism
handles context-level gating. No `__functor` guard or `meta.contextGuard`
needed.

#### parametric.nix (fixedTo/expands)

```nix
parametric.fixedTo.__functor = _: ctx: aspect:
  warn "fixedTo is deprecated" (
    aspect // { __scopeHandlers = constantHandler ctx; }
  );

parametric.expands = attrs: aspect:
  let
    existingHandlers = aspect.__scopeHandlers or {};
    merged = existingHandlers // constantHandler attrs;
  in
  warn "expands is deprecated" (
    aspect // { __scopeHandlers = merged; }
  );
```

These reshape the legacy `__ctx` stamping into `__scopeHandlers` so the
pipeline can consume them.

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

**Consumers (derive scope from handlers):**

- `aspectToEffect` (aspect.nix): wrap `bind.fn` in scope at point of use:
  ```nix
  scopeHandlers = aspect.__scopeHandlers or null;
  resolveFn =
    if scopeHandlers != null
    then fx.effects.scope.stateful scopeHandlers (fx.bind.fn {} fn)
    else fx.bind.fn {} fn;
  ```

- `emitSelfProvide` (aspect.nix): same pattern for provider resolution

- `resolveChildren` (aspect.nix): derive scopeFn from `__scopeHandlers`,
  pass both `__parentScope` (derived) and `__parentScopeHandlers` to
  `emitIncludes`

- `includeHandler` (include.nix): propagate `parentScopeHandlers` only.
  Stop propagating `parentScope`.

- `resolveConditional` (include.nix): stop passing `__parentScope` to
  `emitIncludes`.

- `emitSelfProvide` (aspect.nix): stop stamping `__parentScope` on
  provider includes.

- `default.nix`: drop `__scope` preservation during wrapping

**Structural keys:** Remove `"__scope"` and `"__parentScope"` from
`structuralKeys` in `aspect.nix`.

### resolvedCtx removal (aspect.nix)

The `resolvedCtx` block extracted `resolved.__ctx` from the functor's return
value and composed it into the scope chain. This served two purposes:

1. **Default functor echo** — redundant: parent `__scopeHandlers` already
   provides these args to children.

2. **Deprecated `fixedTo`/`expands`** — now handled by shims stamping
   `__scopeHandlers` directly.

The block is removed entirely. The `tagged` result simplifies to:

```nix
tagged =
  next
  // lib.optionalAttrs (scopeHandlers != null) { __scopeHandlers = scopeHandlers; }
  // lib.optionalAttrs (aspect ? __ctxId) { inherit (aspect) __ctxId; }
  // { __parametricResolved = true; };
```

### What stays

- `__ctx` on ctxApply results — seeds `state.currentCtx` for `into` functions
- `__ctx` stamps from transition handler — entry-point seeding when results
  re-enter `fxResolveTree`
- `__scopeHandlers` propagation — the single source of truth for context

### What's removed

- `__scope` (opaque pre-applied closure) — derived from `__scopeHandlers`
- `__functor`-based guards in `take.nix`, `perCtx`, `forwardWrap`
- `self.__ctx` reads in guard code
- `__ctx` stamping in the default functor
- `resolvedCtx` extraction block in `aspectToEffect`
- The `__ctx` module option in `types.nix` (already removed)
- `meta.contextGuard` mechanism (unnecessary — pipeline uses deferral + handlers)
- `exactly/atLeast/upTo` context-key matching (artifact of manual forwarding)

## Rationale

Under manual context forwarding, `{ host, user }: expr` was called directly
with a context attrset. The function received all keys at once, so guards were
needed to differentiate context levels.

Under handler-based resolution, `bind.fn` compiles the function into chained
effect requests — each arg resolved independently. `{ host, user }: expr` means
"I need both host AND user handlers." If user isn't available, the child is
deferred. The pipeline's deferral + handler probing naturally provides the
correct semantics without any guard mechanism.

The `exactly` distinction ("fire only when scope has these keys and no more")
is unnecessary because `bind.fn` never passes extra args. A function asking for
`{ host }` gets `{ host }` at both host and user levels — the presence of
`user` in the handler scope is invisible to the function.

### Static aspects and identity shims

Some user code wraps static attrsets in `perHost` (e.g., `perHost { nixos = ...; }`).
The identity shim returns these unchanged. This is safe because the transition
structure provides context-level gating: a `perHost`-wrapped aspect is an include
of a HOST-level ctx node. Host-level includes resolve once at host level and do
not re-enter at user level — user level only processes its own includes from the
user ctx node. Deferred includes only re-fire when they were actually deferred
(args not yet available), which doesn't apply to static attrsets (no args to
defer on).

The pipeline structure (which ctx node includes what) is the source of truth for
context-level affinity, not the guard wrappers.

## Files changed

| File | Change |
|------|--------|
| `nix/lib/aspects/fx/aspect.nix` | `forwardWrap`: identity; remove `__scope` reads, derive from `__scopeHandlers`; remove `resolvedCtx` block |
| `nix/lib/aspects/fx/handlers/include.nix` | Remove `meta.contextGuard` handling from `keepChild`; stop propagating `__parentScope` |
| `nix/lib/aspects/fx/handlers/transition.nix` | Stop stamping `__scope`, only stamp `__scopeHandlers` |
| `nix/lib/ctx-apply.nix` | Stop stamping `__scope`, only stamp `__scopeHandlers` |
| `nix/lib/aspects/default.nix` | Drop `__scope` preservation during wrapping |
| `modules/context/perHost-perUser.nix` | Identity + deprecation warning |
| `nix/lib/take.nix` | Identity + deprecation warning |
| `nix/lib/aspects/types.nix` | Default functor: `self: _: self` |
| `nix/lib/parametric.nix` | Update shims to stamp `__scopeHandlers` instead of `__ctx` |
