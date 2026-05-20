# flake-aspects: Palmer Flat Typing — Identity + Defunctionalized Dispatch

**Date:** 2026-05-19 (revised 2026-05-20)
**Status:** Implemented
**Repo:** `../flake-aspects` (github:vic/flake-aspects)
**Commits:** `b63b0ea`, `0e0c8bc`, `9723ee9`

## Problem

flake-aspects' original type system used a 6-type recursive chain to handle function dispatch in aspect positions: `isSubmoduleFn`, `isProviderFn`, `directProviderFn`, `curriedProviderFn`, `providerFn`, `providerType`. This chain was correct but complex, hard to reason about, and tightly coupled to the NixOS module system's `either`/`functionTo` combinators.

Additionally, aspects had no identity tracking — no way to know where an aspect was defined for dedup, tracing, or error messages.

## Solution: Palmer's Flat Typing

Based on Palmer et al. (2024) "Intensional Functions," we replaced the recursive type chain with a single flat `aspectType` that dispatches in its merge body. The key insights:

1. **Defunctionalization**: Functions are wrapped as callable attrsets (`{ __isWrappedFn, __functionArgs, __functor }`). The wrapper is first-order data — inspectable and passable — while `__functor` preserves callability.

2. **`functionTo` for return-value typing**: The wrapper's `__functor` uses `lib.types.functionTo(aspectSubmodule)` semantics. When a wrapped function is CALLED, its return value is automatically typed through `aspectSubmodule`. This gives curried provider chains (e.g., `{ message }: { class, aspect-chain }: { aspect, ... }: { ... }`) correct evaluation — each curry step's result goes through the type system.

3. **`either` for recursion breaking**: `aspectSubmodule` references `aspectType` via `lib.types.either(aspectType, aspectSubmodule)` in `includes` and `provides`. `either` doesn't force its subtypes during construction — only during merge. This breaks the `aspectType → aspectSubmodule → aspectType` infinite type expansion that `lib.types.listOf` and `lib.types.lazyAttrsOf` would cause with a direct reference.

4. **Submodule function detection**: Functions with `_module.args` patterns (`{ aspect, ... }:`, `{ config, ... }:`) are passed directly to `aspectSubmodule.merge` which evaluates them as NixOS modules — NOT wrapped as callable attrsets. This preserves the module evaluation path where `_module.args.aspect = config` is available.

## Design

### Type Architecture

```
aspectsType
  └── freeformType: lazyAttrsOf (aspectType cnf)

aspectType.merge dispatches (two paths):
  single def:
    ├── wrapped fn (__isWrappedFn) → passthrough
    ├── submodule fn (aspect/config/lib/options args) → aspectSubmodule.merge (direct module eval)
    ├── parametric fn → functionTo(aspectSubmodule) + __isWrappedFn tag
    └── attrset → aspectSubmodule.merge
  multi def:
    └── coerce fns to { includes = [fn]; }, aspectSubmodule.merge

aspectOrFn = either(aspectType, aspectSubmodule)  — recursion-safe binding

aspectSubmodule
  ├── freeformType: lazyAttrsOf deferredModule (class content)
  ├── includes: listOf aspectOrFn
  ├── provides: submodule { freeformType: lazyAttrsOf aspectOrFn }
  ├── meta: submodule { freeformType: lazyAttrsOf raw; aspect-chain: listOf str }
  ├── __functor: functorType
  └── resolve, modules: internal
```

### Files Changed

| File | Change | Description |
|---|---|---|
| `nix/types.nix` | **Rewrite** | Replaced 6-type chain with `aspectType` flat dispatch |
| `nix/identity.nix` | **New** | `aspectPath`, `pathKey`, `key`, `structuralKeysSet` |
| `nix/lib.nix` | **Modified** | Exports `identity` |
| `nix/resolve.nix` | **Unchanged** | No modifications needed |

### What Was Eliminated

| Old | Replacement |
|---|---|
| `isSubmoduleFn` | Inline check in `aspectType.merge` |
| `isProviderFn` | Eliminated — `functionTo` handles provider dispatch |
| `directProviderFn` | Eliminated |
| `curriedProviderFn` | Eliminated — `functionTo` with `aspectSubmodule` handles currying |
| `providerFn` | Eliminated |
| `providerType` | `aspectOrFn` = `either aspectType aspectSubmodule` |
| `isModuleFn` export | Eliminated — flat typing handles dispatch internally |

### Defunctionalized Wrapping — The Core Palmer Pattern

In `aspectType.merge`, single-def parametric functions are wrapped inline:

```nix
(lib.types.functionTo (aspectSubmodule cnf)).merge (loc ++ [ "<function body>" ]) defs
// { __isWrappedFn = true; }
```

`lib.types.functionTo(elemType).merge` creates a `{ __functionArgs, __functor }` attrset where `__functor` calls the original function and types the result through `elemType`. By using `aspectSubmodule` as `elemType`, curried provider chains work: each call step types its result, eventually producing a full `aspectSubmodule` with class content.

The `__isWrappedFn = true` tag (Palmer's program-point discriminant) prevents the wrapper from being re-processed by `aspectType` when it appears in `includes` or `provides`.

### Why `either` Breaks the Recursion

`lib.types.listOf(aspectType cnf)` causes stack overflow because `listOf` constructs `aspectType cnf` eagerly. When `aspectSubmodule` has `includes = listOf(aspectType cnf)`, the `listOf` construction forces `aspectType cnf` which includes a closure over `aspectSubmodule cnf` in its merge body. Nix's attrset construction evaluates closures' captured bindings, triggering `aspectSubmodule cnf` construction.

`lib.types.either(t1, t2)` accesses `t1.name` and `t2.name` during construction but does NOT evaluate `t1.merge` or `t2.merge`. The merge bodies — which contain the recursive references — remain lazy. This is why `aspectOrFn = either aspectType aspectSubmodule` is safe for `includes` and `provides`.

### Den Integration

`isModuleFn` was removed from the public API. Den's `providerType` chain (`isSubmoduleFn`, `isProviderFn`, `directProviderFn`, `curriedProviderFn`, `providerFn`, `providerType`, `coercedProviderType`, `aspectContentType`, `aspectKeyType`) can be replaced by consuming `aspectType`/`aspectOrFn`/`aspectSubmodule` directly. The flat typing handles module vs parametric dispatch internally — den doesn't need external classification heuristics.

## Testing

32/32 tests pass:
- 21 original tests — all pass unchanged
- 4 identity tests (key, path, structural keys)
- 3 parametric wrapper tests (wrapper shape, callable, multidef)
- 2 nested identity tests (aspect-chain threading)
- 2 parametric multidef tests

## Public API

```nix
{
  aspectsType    # Top-level container: submodule with lazyAttrsOf aspectType
  aspectSubmodule  # Aspect shape: name, meta, includes, provides, __functor, resolve
  aspectType     # Flat dispatch: defunctionalize fns, merge attrsets through aspectSubmodule
}
```

Plus existing unchanged exports: `transpose`, `aspects`, `new`, `new-scope`, `forward`, `resolve`, `identity`.

## Theoretical Foundation

| Palmer concept | Implementation | Where |
|---|---|---|
| Defunctionalization | `functionTo(aspectSubmodule) // { __isWrappedFn }` | `aspectType.merge` single-def parametric path |
| Program point tag | `__isWrappedFn = true` | Wrapper passthrough detection |
| Return-value typing | `lib.types.functionTo(aspectSubmodule)` | Curried chain support |
| Lazy substitution (§4) | `either` defers type construction | Recursion breaking |
| Conservative equality | `identity.key` (aspect-chain + name) | Future dedup support |
| Closure inspection | `__functionArgs` on wrappers | Inspectable without calling |
