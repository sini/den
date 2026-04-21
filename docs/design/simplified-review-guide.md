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
- `fx.effects.scope.provide` — nix-effects scope handler (state-transparent reader pattern). Installs `__scopeHandlers` for parametric resolution
- `has-handler` effect — queries whether a named handler exists in scope (replaces earlier `probe-arg` effect). Used to check parametric arg availability before resolution

**The trampoline** — The interpreter loop from `nix-effects`. Takes a computation and a handler set. Runs the computation step by step. When it hits an effect, calls the matching handler, gets a resume value, continues. Uses `genericClosure` for stack safety (no recursion limit).

### How a host gets resolved

```
1. Pipeline starts with the "flake" aspect
2. flake has into.flake-system → fans out per system (x86_64-linux, aarch64-darwin)
3. flake-system has into.flake-os → fans out per host (igloo, iceberg)
4. Each host's aspects are compiled via aspectToEffect
5. Parametric aspects ({ host }: ...) get their args resolved via bind.fn
   → bind.fn sends a "host" effect
   → scope.provide installs __scopeHandlers (built via constantHandler) for the subtree
   → the scoped handler provides the host entity back to bind.fn
6. Each resolved aspect's class keys (nixos, homeManager) are emitted
7. classCollectorHandler collects matching modules
8. Result: list of NixOS modules for this host
```

### Context propagation: __scopeHandlers and scope.provide

The branch went through several iterations on how context (host, user) reaches nested aspects:

**Attempt 1 — scope.run:** Wrap a subtree in a handler. Clean, but effect rotation lost context crossing scope boundaries.

**Attempt 2 — __ctx tagging (ctx-as-data):** Tag each aspect with `__ctx = { host, user }`. `aspectToEffect` wraps `bind.fn` in a scoped handler. Simpler, but context didn't propagate to children's includes automatically.

**Attempt 3 — scope.stateful:** State fork-join pattern. Worked with deep handlers but dropped 79% of class collector events because state forks are isolated — class emissions inside a scope.stateful block didn't reach the parent accumulator.

**Current — scope.provide + __scopeHandlers:** The branch now uses `scope.provide` (state-transparent reader pattern from nix-effects). Transitions tag target aspects with `__scopeHandlers` — a plain attrset of handler records built via `constantHandler`. At point of use, `aspectToEffect` calls `fx.effects.scope.provide scopeHandlers` to install them for `bind.fn` resolution. This is transparent to state — class collector events pass through unchanged.

The `__scope` and `__parentScope` attrs are removed. `__scopeHandlers` is the single source of truth for context. `fixedTo`/`expands` deprecation shims stamp `__scopeHandlers` directly via `constantHandler`. Parent and resolved `__scopeHandlers` are merged in the tagged block of `aspectToEffect`.

`__ctx` remains only at entry points (ctxApply stamps it for positional-arg providers). `__parentCtx` is gone entirely — replaced by `__parentScopeHandlers` (handler propagation) and `__parentCtxId` (fan-out identity propagation).

### Internal `__`-prefixed tags

With `scope.provide` in place, the context workarounds are mostly cleaned up:

- `__ctx` — **Stays at entry points only.** `ctxApply` stamps it for positional-arg providers (bare `_:` lambdas that can't use `bind.fn`). Not used for general context propagation — that's `__scopeHandlers` now.
- `__parentCtx` — **Removed.** Replaced by `__parentScopeHandlers` (handler propagation to children) and `__parentCtxId` (fan-out identity propagation).
- `__scope` / `__parentScope` — **Removed.** Were intermediate attempts at scope-based context. `__scopeHandlers` is the single source of truth.
- `__scopeHandlers` — **New, stays.** Plain attrset of handler records (built via `constantHandler`). Transitions stamp this on target aspects. `aspectToEffect` installs them via `scope.provide`. `fixedTo`/`expands` shims also stamp this.
- `__fn` / `__args` — **New, stays.** Parametric wrapper fields replacing `__functor`/`__functionArgs`. `__fn` is the resolution function, `__args` is the function args attrset. Detected by `isParametricWrapper` and the `parametricType` in `types.nix`.
- `__ctxId` — **Stays.** Distinguishes fan-out instances (`tux/{igloo}` vs `tux/{iceberg}`). Computed by the transition handler.
- `__parametricResolved` — **Stays.** Tells `classCollectorHandler` to preserve `__ctxId` in module keys (different content per context = don't dedup).

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

**`types.nix`** (~210 lines changed): `providerType` reworked to wrap bare parametric functions with identity (name, meta.provider) from their declaration location. A `parametricType` with `isParametricWrapper` check now handles `{ __fn; __args; }` wrappers — `providerType.merge` early-exits for these, preventing submodule merge from capturing `__scopeHandlers` in freeform `deferredModule`. `__functor`/`__functionArgs` removed from `aspectSubmodule` — only `ctxSubmodule` (in `ctx-types.nix`) retains `__functor` for backward-compat callable ctx nodes. On main, provider functions were opaque lambdas.

**`tree.nix`** (constraint cascading): `check-constraint` now uses prefix matching on identity paths, so excluding `monitoring` cascades to `monitoring/node-exporter`.

### Provider simplification across modules

The most widespread change across `modules/`: removal of `parametric.fixedTo` and `parametric.exactly` wrappers from provider definitions. These existed to pin context values for the legacy resolver. With the fx pipeline's `scope.provide` + `__scopeHandlers` propagation, providers are plain attrsets:

```nix
# Before (on main):
den.ctx.host.provides.host = { host }: parametric.fixedTo { inherit host; } host.aspect;

# After (this branch):
den.ctx.host.provides.host = { host }: host.aspect;
```

Affected: `host-aspects.nix`, `mutual-provider.nix`, `user-shell.nix`, `host.nix`, `user.nix`, `define-user.nix`, `inputs.nix`, `self.nix`, and more. The `__ctx` tag on the resolved aspect carries context that `fixedTo` used to pin explicitly.

Also: `namespace.nix` now strips `__fn`, `__args`, `__scopeHandlers`, and `__ctx` from namespace denfuls to prevent pipeline-internal tags from leaking into namespace definitions.

**`has-aspect.nix`** (rewritten): Now uses the fx pipeline's `pathSet` (accumulated during resolution via `collectPathsHandler`) instead of running a separate legacy resolve.

### Key new mechanisms (not on main)

- **`parametricType` + `isParametricWrapper`** — A dedicated type in `types.nix` for `{ __fn; __args; }` wrappers. `providerType.merge` early-exits when it detects parametric wrappers, preventing submodule merge from capturing `__scopeHandlers` in freeform `deferredModule`.
- **`scope.provide` for handler installation** — State-transparent reader pattern from nix-effects. `aspectToEffect` calls `fx.effects.scope.provide scopeHandlers` when `__scopeHandlers` is present. Replaced `scope.stateful` which dropped class collector events.
- **`__scopeHandlers` as single context source** — Transitions, `fixedTo`, `expands` all stamp `__scopeHandlers` via `constantHandler`. Parent and resolved scopeHandlers merge in `aspectToEffect`'s tagged block.
- **`has-handler` effect** — Replaces the earlier `probe-arg` effect. Queries the handler scope directly (including scoped handlers from `scope.provide`) to check if a parametric arg is available. Pure Nix check against `__scopeHandlers` first, then `has-handler` for root handlers.
- **Deferred includes** — When `has-handler` returns false, the include is parked in `state.deferredIncludes`. When context widens (a transition provides new args), deferred includes are drained and resolved.
- **`__ctxId` fan-out identity** — Each context value in a fan-out (e.g., 50 hosts) gets a unique identity suffix so module dedup doesn't collapse distinct results.
- **`__parametricResolved` flag** — Marks aspects resolved through `bind.fn` so the class collector preserves their ctxId in module keys (different content per context = don't dedup).
- **`mergeInto` for into defs** — Multiple `into` definitions (fn-form and attrset-form) now concatenate their context value lists instead of last-wins replacement.
- **`fixedTo`/`expands` return parametric wrappers** — Deprecation shims produce `{ __fn; __args; __scopeHandlers; }` wrappers to survive `providerType` submodule merge.
- **take.exactly/perCtx produce `__fn`/`__args` wrappers** — Deprecation shims updated to emit parametric wrappers instead of using `__functor`/`__functionArgs`.
- **`config.den or {}` fallback** — `flakeOutputs.nix` uses graceful fallback for inner evalModules handling.

### Commit phases

**Phase 1** (`bc6147ff`–`64e07bdb`): Remove legacy — delete adapters/resolve/statics, gut parametric, remove feature gate.

**Phase 2** (`acc31b54`–`29421ecc`): Stabilize — fix breakage from removal. Context propagation, provider type merging, ctxApply, functor handling. Several approaches tried and reverted.

**Phase 3** (`6ed013ec`–`98f2f785`): Rearchitect — ctx-as-data approach, probe-arg, deferred includes, native transitions.

**Phase 4** (`64325863`–`120bc2d4`): Edge cases — fan-out identity, cross-provider dedup, perCtx, constraint cascading, take reimplementation.

**Phase 5** (`f5f80529`–`16f3778e`): Targeted fixes — fan-out module dedup, has-aspect identity, positional-arg providers, integer ctxId, into merge.

**Phase 6** (recent): Parametric type separation — `__fn`/`__args` replace `__functor`/`__functionArgs`, `parametricType` added, `scope.provide` replaces `scope.stateful`, `__scope`/`__parentScope`/`__parentCtx` removed, `fixedTo`/`expands`/`take`/`perCtx` shims updated to produce parametric wrappers, `meta.contextGuard` replaces `__functor` guards, `config.den or {}` fallback in `flakeOutputs.nix`.

## Current test status: 431/464 tests pass (33 failures, 10 unique)

Down from 6 baseline failures before the scope.provide / parametricType changes landed. The new failures are concentrated in:

| Area | Tests | Problem |
|---|---|---|
| perUser-perHost | perUser-perHost tests | Context propagation through fan-out transitions — `__scopeHandlers` not reaching nested perCtx wrappers correctly |
| ctx-transformation | ctx-transformation | Mix of positional-arg includes and context guard mismatches |
| standalone-homes | standalone-homes | Home-manager standalone configs not receiving host context through provide chain |
| forward | forward-alias-class, forward-flake-level | `forward.nix` starts fresh pipeline, loses scoped handlers |

## What's next: relationship policies

The spec at `docs/superpowers/specs/2026-04-20-relationship-policies-design.md` proposes generalizing `into` transitions as first-class **relationship policies**.

### Core idea

Instead of `into` being a special-case fan-out mechanism, each relationship between entities (host→user, host→peer, user→home) is a named policy with:

- **Per-relationship named effect handlers** — Each relationship installs its own named handler (e.g., `"peer"` handler for host→peer). Aspects query the relationship by name via effects, not by convention.
- **Two-phase provide-to** — Cross-entity routing (host A contributing config to host B) uses a collection phase followed by a distribution phase, replacing the need for forward.nix's fresh pipeline.

### Immediate priorities

1. **Fix remaining test failures** — The ~10 failures in perUser-perHost, ctx-transformation, and standalone-homes need targeted fixes to `__scopeHandlers` propagation.
2. **Remove `__ctx` from non-entry-point paths** — Currently `__ctx` lingers in some include handler paths. It should only exist at ctxApply entry points.
3. **Implement relationship policies** — Replace `into` with the generalized policy mechanism, enabling cross-entity contributions without special-case forward machinery.

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
    types.nix       — aspectType, providerType, parametricType, isParametricWrapper
    has-aspect.nix  — hasAspectIn, collectPathSet, mkEntityHasAspect
    default.nix     — fxResolveTree, resolve entry point

modules/outputs/
  osConfigurations.nix — orchestration: flake-system → flake-os → host configs
```

## Glossary

- **Aspect** — A named, addressable config bundle. Has class keys (nixos, homeManager), includes (children), and optionally provides (sub-aspects) and into (transitions). Plain attrsets — no `__functor`.
- **Effect** — A value emitted by a computation. The computation pauses until a handler provides a resume value. Like throwing an exception that gets caught and answered.
- **Handler** — A function that catches a specific effect name and returns `{ resume; state; }`. Resume is the value sent back to the computation. State is the accumulated pipeline state.
- **Trampoline** — The interpreter loop. Runs computations iteratively using `genericClosure` for stack safety. One step per effect.
- **bind.fn** — Resolves a parametric function's named args by sending each arg name as an effect. `{ host }: ...` sends a "host" effect, gets the host entity back, calls the function.
- **Class key** — A top-level key on an aspect that names a class: `nixos`, `homeManager`, `hjem`, etc. The classCollector only keeps modules for the target class.
- **Transition** — An `into` declaration that fans out to child contexts. `host.into.user` creates one resolution per user on the host.
- **Parametric wrapper** — An attrset with `__fn` (resolution function) and `__args` (function args). Replaces `__functor`/`__functionArgs`. Detected by `isParametricWrapper`. Survives `providerType` submodule merge via `parametricType` early-exit.
- **scope.provide** — nix-effects primitive that installs handlers for a subtree without forking state. Used to install `__scopeHandlers` (context handlers) at point of use in `aspectToEffect`.
- **__scopeHandlers** — Plain attrset of handler records (built via `constantHandler`). Single source of truth for context propagation. Stamped by transitions, `fixedTo`/`expands` shims, and merged in `aspectToEffect`.
- **has-handler** — nix-effects effect that queries whether a named handler exists in the current scope. Replaces `probe-arg`. Used by the include handler to check parametric arg availability before resolution.
- **constantHandler** — Handler factory in `ctx.nix`. Takes a ctx attrset (`{ host, user }`) and produces handlers that resume with the corresponding value when queried.
- **Relationship policy** (future) — Generalization of `into` transitions. Each entity relationship is a named policy with its own effect handlers and cross-entity routing. Proposed in the relationship policies spec.
- **Capability** (future) — Generalization of class keys. Any named activation point: a class, a feature flag, an entity name. Not yet implemented.

## TL;DR

This branch deletes den's legacy recursive resolver (~450 lines across 4 files) and makes the fx effects pipeline the only pipeline. The fx handlers — previously stubs that delegated to legacy code — now own everything: include resolution, transitions, parametric args, context propagation, dedup, constraints.

The biggest user-visible change: `parametric.fixedTo`/`parametric.exactly` wrappers are gone from providers. Context flows through the pipeline natively via `scope.provide` and `__scopeHandlers` instead of being pinned manually. Pipeline wrappers use `__fn`/`__args` instead of `__functor`/`__functionArgs`, with a dedicated `parametricType` that survives submodule merge.

\*\*431/464 tests pass\*\* (10 unique failures). Failures are concentrated in perUser-perHost, ctx-transformation, and standalone-homes tests. The next design direction is **relationship policies** — generalizing `into` transitions as first-class policies with per-relationship named effect handlers and two-phase provide-to for cross-entity routing.

Net code change: +1118 / -1161 lines across 37 files. The pipeline grew (handlers do more), but the legacy layer it replaced was larger. `parametric.nix` went from 177 to 26 lines. `ctxApply` went from 124 to 56. The adapter layer (349 lines) is gone entirely.
