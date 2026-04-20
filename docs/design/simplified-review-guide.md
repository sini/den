# Simplified Review Guide for feat/rm-legacy

A plain-language walkthrough of what this branch does, how the pipeline works now, and what's left. Written for someone who understands programming but hasn't read every commit.

## What is den?

Den is a Nix framework for managing fleets of machines. You declare hosts, users, and "aspects" (reusable config bundles). Den's job is to take these declarations and produce NixOS/home-manager configs for each machine.

```nix
den.hosts.x86_64-linux.igloo.users.tux = {};

den.aspects.igloo.nixos.networking.hostName = "igloo";
den.aspects.tux.homeManager.programs.git.enable = true;
```

The **resolution pipeline** is the engine that turns these declarations into actual NixOS modules. This branch rewrites that engine.

## What did the old pipeline do?

The old pipeline was a recursive tree walker. It visited each aspect, checked what context was available (which host? which user?), called parametric functions with the right args, and collected the results. The recursion was manual — each step knew about the next.

Problems:
- Context threading was manual. Every new feature (constraints, tracing, dedup) meant touching the recursion logic.
- Bugs were easy: forget to thread context, lose a value, get infinite recursion. PRs 408-437 were ALL caused by manual context threading mistakes.

## What does the new pipeline do?

The new pipeline uses **algebraic effects** (via the `nix-effects` library). Instead of recursive tree walking, aspects are compiled into **computations** that emit **effects**. Handlers decide what to do with each effect. The trampoline (interpreter) runs the computation.

Think of it like this:

```
Old: function calls function calls function (manual plumbing)
New: computation emits event → handler catches it → decides what to do
```

### The key players

**aspectToEffect** — The compiler. Takes an aspect attrset and produces a computation:
```
{ nixos = {...}; includes = [...]; }
  → emit "emit-class" {class="nixos"; module={...}}
  → emit "emit-include" {child=...} for each include
```

**Handlers** — Each handler catches one type of effect:
- `constantHandler` — provides context values (host, user, class) when asked via effects
- `classCollectorHandler` — collects NixOS/HM modules that match the target class
- `includeHandler` — processes child aspects (wraps, resolves, recurses). Resume is a computation, not a plain value — this is how handler-driven recursion works
- `transitionHandler` — handles `into` transitions (host→user fan-out, cross-providers)
- `constraintRegistryHandler` — manages exclude/substitute rules
- `chainHandler` — tracks parent→child provenance
- `collectPathsHandler` / `pathSetHandler` — records which aspects were resolved (for `hasAspect` and `includeIf` guards)
- `ctxSeenHandler` — dedup for transitions (don't re-resolve the same ctx target)
- `deferredIncludeHandler` / `drainDeferredHandler` — parks parametric includes whose args aren't available yet, resolves them later when context widens
- `fx.effects.state.handler` — nix-effects state effect handler (from the library, not den)

**The trampoline** — The interpreter loop from `nix-effects`. Takes a computation and a handler set. Runs the computation step by step. When it hits an effect, calls the matching handler, gets a resume value, continues. Uses `genericClosure` for stack safety (no recursion limit).

### How a host gets resolved

```
1. Pipeline starts with the "flake" aspect
2. flake has into.flake-system → fans out per system (x86_64-linux, aarch64-darwin)
3. flake-system has into.flake-os → fans out per host (igloo, iceberg)
4. Each host's aspects are compiled via aspectToEffect
5. Parametric aspects ({ host }: ...) get their args resolved via bind.fn
   → bind.fn sends a "host" effect
   → a scoped constantHandler (built from the aspect's `__ctx`) provides the host entity
   (with scope.stateful, this scoping happens automatically for the entire subtree)
6. Each resolved aspect's class keys (nixos, homeManager) are emitted
7. classCollectorHandler collects matching modules
8. Result: list of NixOS modules for this host
```

### Context as data vs. scoped handlers

The branch tried two approaches for providing context (host, user) to nested aspects:

**Scoped handlers (scope.run):** Wrap a subtree's computation in a handler that provides context values. Any effect inside the scope sees the handler. Clean, but broken — effect rotation lost context when crossing scope boundaries.

**Context as data (__ctx tagging):** Tag each aspect with `__ctx = { host, user }`. When `aspectToEffect` sees `__ctx`, it wraps only the `bind.fn` call in a scoped handler. Simpler, but context doesn't propagate to children's includes automatically.

The branch currently uses ctx-as-data. The spec proposes going back to scoped handlers (`scope.stateful`) now that nix-effects has **deep handler semantics** (commit `23965f1`) — the bug that broke scope.run is fixed.

### Why `__ctx` and `__parentCtx` exist (and why they should go away)

These are **workarounds for broken scope.run**, not permanent architecture:

- `__ctx` — A tag on aspect attrsets carrying context values (`{ host, user }`). Exists because `scope.run`/`scope.stateful` lost context during effect rotation. In the proper design, scoped handlers provide these values to the entire subtree.
- `__parentCtx` — Manual plumbing to propagate `__ctx` from parent to children's includes. In the proper design, scoped handlers propagate naturally — children inherit parent handlers.

**If `scope.stateful` works with deep handlers, both go away.**

Some `__`-prefixed tags **stay** because they serve identity/dedup, not context:

- `__ctxId` — Distinguishes fan-out instances (`tux/{igloo}` vs `tux/{iceberg}`). Without it, module dedup collapses distinct fan-out results. Stays, but computed by the transition handler instead of derived from `__ctx`.
- `__parametricResolved` — Tells `classCollectorHandler` whether to preserve `__ctxId` in module keys. Parametric resolutions produce different content per context and must not dedup. Stays.

## What's different from main

On `origin/main`, the fx pipeline exists **alongside** the legacy resolver. The legacy code does the real work — `adapters.nix` (349 lines), `resolve.nix` (68 lines), `statics.nix` (32 lines), and `parametric.nix` (195 lines) implement recursive tree-walking resolution. The fx pipeline mirrors this flow, delegating to the same adapter machinery. There's a `fxPipeline` feature gate to switch between them.

This branch **removes the legacy pipeline entirely** and makes the fx pipeline stand on its own with a fundamentally different architecture:

### What was deleted

| File | Lines | What it did |
|---|---|---|
| `adapters.nix` | 349 | Legacy adapter layer — bridged aspects to the module system |
| `resolve.nix` | 68 | Legacy recursive resolve function |
| `statics.nix` | 32 | Static aspect handling |
| `fxPipeline.nix` | 11 | Feature gate (no longer needed) |
| `parametric.nix` | 177→26 | Gutted — fx pipeline handles parametric resolution natively via `bind.fn` |

### What was rearchitected

The fx handlers on main were stubs that delegated to legacy code. This branch made them own their full responsibility:

**`include.nix`** (189→311 lines): The include handler now owns ALL include resolution — child wrapping (`wrapChild`), parametric detection, NixOS module function normalization, constraint checking, deferred includes for unresolvable args, and context propagation. On main, most of this lived in `adapters.nix`.

**`transition.nix`** (101→232 lines): The transition handler now implements full ctx-as-data transitions — fan-out to multiple context values, cross-provider resolution, ctx-seen dedup, and deferred include draining. On main, transitions delegated to `ctxApply` and the legacy resolver.

**`aspect.nix`** (221→390 lines): The aspect compiler now handles parametric resolution via `bind.fn` effects, forward wrapping for exact-match context guards, self-provide with positional-arg support, class emission, and constraint registration. On main, parametric resolution lived in `parametric.nix`.

**`ctxApply`** (124→56 lines): On main, `ctxApply` did resolution — it called the provider function, merged results, handled transitions. Now it's just a bridge: tags the aspect with `__ctx` and preserves `into`/`provides`/`includes` for the pipeline to handle natively.

**`types.nix`** (~210 lines changed): `providerType` reworked to wrap bare parametric functions with identity (name, meta.provider) from their declaration location. This enables `hasAspect` lookups on provider refs. On main, provider functions were opaque lambdas.

**`tree.nix`** (constraint cascading): `check-constraint` now uses prefix matching on identity paths, so excluding `monitoring` cascades to `monitoring/node-exporter`.

### Provider simplification across modules

The most widespread change across `modules/`: removal of `parametric.fixedTo` and `parametric.exactly` wrappers from provider definitions. These existed to pin context values for the legacy resolver. With the fx pipeline's `__ctx` propagation (and eventually `scope.stateful`), providers are plain attrsets:

```nix
# Before (on main):
den.ctx.host.provides.host = { host }: parametric.fixedTo { inherit host; } host.aspect;

# After (this branch):
den.ctx.host.provides.host = { host }: host.aspect;
```

Affected: `host-aspects.nix`, `mutual-provider.nix`, `user-shell.nix`, `host.nix`, `user.nix`, `define-user.nix`, `inputs.nix`, `self.nix`, and more. The `__ctx` tag on the resolved aspect carries context that `fixedTo` used to pin explicitly.

Also: `namespace.nix` now strips `__functor` and `__ctx` from namespace denfuls to prevent pipeline-internal tags from leaking into namespace definitions.

**`has-aspect.nix`** (rewritten): Now uses the fx pipeline's `pathSet` (accumulated during resolution via `collectPathsHandler`) instead of running a separate legacy resolve.

### Key new mechanisms (not on main)

- **`probe-arg` effect** — Asks "is this parametric arg available?" before trying to resolve. Enables skipping unresolvable includes instead of erroring.
- **Deferred includes** — When `probe-arg` returns false, the include is parked in `state.deferredIncludes`. When context widens (a transition provides new args), deferred includes are drained and resolved.
- **`__ctxId` fan-out identity** — Each context value in a fan-out (e.g., 50 hosts) gets a unique identity suffix so module dedup doesn't collapse distinct results.
- **`__parametricResolved` flag** — Marks aspects resolved through `bind.fn` so the class collector preserves their ctxId in module keys (different content per context = don't dedup).
- **`mergeInto` for into defs** — Multiple `into` definitions (fn-form and attrset-form) now concatenate their context value lists instead of last-wins replacement.
- **take.exactly/atLeast/upTo** — Reimplemented as context guards using `self.__ctx` matching, replacing the legacy `parametric.nix` machinery.
- **perCtx wrappers** — `perHost`/`perUser`/`perHome` use `self.__ctx` exact match with includes-based structure for trace provenance.

### Commit phases

**Phase 1** (`bc6147ff`–`64e07bdb`): Remove legacy — delete adapters/resolve/statics, gut parametric, remove feature gate.

**Phase 2** (`acc31b54`–`29421ecc`): Stabilize — fix breakage from removal. Context propagation, provider type merging, ctxApply, functor handling. Several approaches tried and reverted.

**Phase 3** (`6ed013ec`–`98f2f785`): Rearchitect — ctx-as-data approach, probe-arg, deferred includes, native transitions.

**Phase 4** (`64325863`–`120bc2d4`): Edge cases — fan-out identity, cross-provider dedup, perCtx, constraint cascading, take reimplementation.

**Phase 5** (`f5f80529`–`16f3778e`): Targeted fixes — fan-out module dedup, has-aspect identity, positional-arg providers, integer ctxId, into merge.

## Current test status: 458/464

Six remaining failures, all related to **context not crossing resolution boundaries**:

| Test | Problem |
|---|---|
| forward-alias-class | `forward.nix` starts fresh pipeline, loses context |
| forward-flake-level | Same — detectHost gets wrong args |
| os-class | Same — nixosConfigurations not generated |
| has-aspect E | User aspect can't see `host` from transition |
| os-user | Same — parametric include needs `host` in user scope |
| ctx-transformation | Mix of above + positional-arg includes |

## What's next: the spec

The spec at `docs/superpowers/specs/2026-04-19-provide-to-effects-design.md` proposes:

### Pre-work: scope.stateful for transitions

Now that deep handlers work in nix-effects, restore `scope.stateful` for transitions. This makes host/user available as handled effects for the entire subtree — fixing the 3 cross-scope failures without new machinery.

### provide-to: cross-entity forwarding

For the remaining cases (forward mechanism, cross-host contributions), a two-phase approach:

**Phase 1** — The pipeline runs normally. When a transition targets a sibling entity (e.g., host→peer where peer is another host), the resolved modules are collected in `state.provideTo` instead of going to the current classCollector.

**Phase 2** — After all entities resolve, the orchestration layer distributes collected modules to their targets. Injected modules are regular dendritic aspects with class keys. No re-resolution needed — just module list concatenation.

Cross-entity contributions look like regular parametric aspects:

```nix
# Regular parametric include — { peer } resolved via host.into.peer
({ peer, ... }:
  lib.optionalAttrs (peer.hasAspect den.aspects.loadbalancer) {
    nixos.services.haproxy.frontends.app.backends = [
      { address = host.meta.ip; port = 8080; }
    ];
  }
)
```

No special API. The pipeline detects cross-entity transitions and routes internally.

## File map

```
nix/lib/aspects/fx/
  aspect.nix        — aspectToEffect: compiles aspects into computations
  pipeline.nix      — mkPipeline, defaultHandlers, fxResolve
  identity.nix      — aspect identity paths, pathSet, tombstones
  handlers/
    include.nix     — emit-include: wraps children, resolves parametric args
    transition.nix  — into-transition: ctx fan-out, cross-providers
    ctx.nix         — constantHandler (provides context values), ctxSeenHandler (dedup)
    tree.nix        — classCollector, constraints, chain tracking, deferred includes

nix/lib/
  ctx-types.nix     — ctxTreeType (exports); internally uses intoCtxType for into merge, ctxSubmodule for ctx nodes
  ctx-apply.nix     — ctxApply (__functor for ctx nodes)
  forward.nix       — forwardEach (class-to-class forwarding)
  aspects/
    types.nix       — aspectType, providerType, coercedProviderType
    has-aspect.nix  — hasAspectIn, collectPathSet, mkEntityHasAspect
    default.nix     — fxResolveTree, resolve entry point

modules/outputs/
  osConfigurations.nix — orchestration: flake-system → flake-os → host configs
```

## Glossary

- **Aspect** — A named, addressable config bundle. Has class keys (nixos, homeManager), includes (children), and optionally provides (sub-aspects) and into (transitions).
- **Effect** — A value emitted by a computation. The computation pauses until a handler provides a resume value. Like throwing an exception that gets caught and answered.
- **Handler** — A function that catches a specific effect name and returns `{ resume; state; }`. Resume is the value sent back to the computation. State is the accumulated pipeline state.
- **Trampoline** — The interpreter loop. Runs computations iteratively using `genericClosure` for stack safety. One step per effect.
- **bind.fn** — Resolves a parametric function's named args by sending each arg name as an effect. `{ host }: ...` sends a "host" effect, gets the host entity back, calls the function.
- **Class key** — A top-level key on an aspect that names a class: `nixos`, `homeManager`, `hjem`, etc. The classCollector only keeps modules for the target class.
- **Transition** — An `into` declaration that fans out to child contexts. `host.into.user` creates one resolution per user on the host.
- **Capability** (future) — Generalization of class keys. Any named activation point: a class, a feature flag, an entity name. Not yet implemented.
