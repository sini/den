# provide-to: Cross-boundary context forwarding via effects

## Problem

The fx pipeline resolves aspects in isolated scopes. Context flows down (parent to child via `__ctx`) but not across resolution boundaries. This blocks cross-host forwarding and is likely related to several existing test failures.

Three boundary types are affected:

1. **Fresh pipeline runs** (forward mechanism): `forward.nix` calls `den.lib.aspects.resolve` starting a new pipeline that loses parent context.
2. **Transition propagation**: Parametric includes in user aspects can't see `host` from the transition that resolved their parent.
3. **Cross-host** (new, untested): Host A can't contribute modules to host B's config (e.g., `/etc/hosts` with fleet IPs, SSH `known_hosts`).

## Rejected alternatives

### A. Inherited context chain

Thread parent context into child pipeline runs via an `inheritCtx` parameter. Simpler, but cycles are prevented by API discipline (only pass entity metadata, not resolution results) rather than by construction. Also doesn't generalize to sibling-to-sibling (cross-host) forwarding without additional mechanisms.

### B. Simpler ctx threading for existing failures

Some existing failures (cross-scope context, forward) might be fixable by threading `currentCtx` through `extraState` or fixing `__parentCtx` propagation without new effects. This was considered but doesn't address the cross-host use case and would be a partial fix — the provide-to mechanism handles all three boundary types uniformly.

## Solution: Two-phase resolution with `provide-to` effects

### Phase 1: Normal resolution with collection

The pipeline runs normally. A new `provide-to` effect lets any aspect declare modules targeting a different resolution scope. These are collected in pipeline state, not resolved immediately.

```nix
# In a host aspect — provide to sibling hosts:
{ host, ... }: {
  nixos.networking.hostName = host.name;
  includes = [
    (den.provides.to "host" {  # "host" = sibling hosts (same ctx type as emitter)
      guard = targetCtx: lib.mkIf (targetCtx.host.name != host.name);
      module = { networking.extraHosts = "${host.meta.ip} ${host.name}"; };
    })
  ];
}
```

The `provide-to` handler collects emissions without resolving them:

```nix
provideToHandler = {
  "provide-to" = { param, state }: {
    resume = null;
    state = state // {
      # Thunk chain — _: prevents deepSeq from forcing contents.
      # The dummy parameter is never meaningful (always called with null).
      provideTo = _: ((state.provideTo or (_: [])) null) ++ [param];
    };
  };
};
```

### Phase 2: Distribution at orchestration level

After phase 1 completes, the caller (e.g., `osConfigurations.nix`) reads `state.provideTo null`, groups emissions by target, and injects them as additional modules when building target configs.

```
flake
  -> flake-system (per system)
    -> flake-os (per host)         # Phase 1: resolve each host, collect provide-to
    -> distribute provide-to       # Phase 2: group by target, inject into targets
    -> build target configs        # Target pipelines receive injected modules
```

Phase 2 is one-directional: the `provide-to` handler is NOT installed in phase 2 pipeline runs. Injected modules cannot emit further `provide-to` effects. This prevents cycles structurally.

**Limitation:** Modules injected in phase 2 cannot themselves use `provide-to`. If a cross-host module also needs cross-class forwarding (e.g., fleet SSH config that also needs home-manager integration), that must be expressed as a regular class key on the injected module, not as a nested `provide-to`. This is acceptable — cross-class forwarding within a single entity is a different mechanism (class keys + forward) that already works.

### Forward mechanism migration

`forward.nix` currently does:
1. Call `den.lib.aspects.resolve fromClass asp` (fresh pipeline, loses context)
2. Apply `mapModule` to the resolved source module
3. Wrap with guards, adapters, `intoPath` routing
4. Return the wrapped module as a class key

The migration:
- Step 1 (resolve) stays in phase 1 — the source aspect's pipeline still runs normally and produces a source module.
- Steps 2-4 (mapModule, guards, adapters) also stay in phase 1 — these transform the resolved module into its final shape.
- The **result** of steps 1-4 is emitted as a `provide-to` instead of being returned directly as a class key.

The key insight: `forward.nix` doesn't need to change its internal resolution logic. It only changes WHERE the result goes — from a direct class key return to a `provide-to` emission that the orchestration layer distributes. The adapter/guard/mapModule machinery stays intact.

### Target routing: graph-based, context-type agnostic

The `provide-to` target names a **ctx node** (or path of ctx nodes). Routing is determined by the emitter's position in the `den.ctx` transition graph — not by hardcoded scope qualifiers.

The transition graph defines relationships:
```
flake-system
  host (per host, via flake-system.into.host or similar)
    user (per user, via host.into.user)
    hm-user (per user, via host.into.hm-user)
  environment (user-defined)
    host (per host, via environment.into.host)
```

The same target name routes differently depending on where the emission originates:

| Emitter scope | Target | Routing | Result |
|---|---|---|---|
| host aspect | `"user"` | follows `host.into.user` | my host's users |
| host aspect | `"host"` | follows parent's `into.host` | sibling hosts |
| environment aspect | `"host"` | follows `environment.into.host` | hosts in my environment |
| host aspect | `["host", "user"]` | siblings, then their users | users on other hosts |

**Single-hop targets** (string): `"user"`, `"host"` — one step through the transition graph. If the target is a CHILD ctx of the emitter, it follows the emitter's `into.${target}`. If it's a SIBLING (same ctx type as the emitter), it follows the parent's `into.${target}`.

**Multi-hop targets** (list of strings): `["host", "user"]` — walk the graph: first hop to sibling hosts, then from each host to their users. The orchestration layer evaluates each hop, fanning out at each step.

**Named entity targets** (attrset): `{ host = "igloo"; }` — target a specific entity by name. The orchestration layer filters to matching entities.

This makes provide-to fully context-type agnostic — it works for any ctx node, including user-defined ones like `environment`, `cluster`, or `region`. The transition graph IS the routing table.

**Class-level targeting** (e.g., "put this in the nixos class") is NOT part of the `provide-to` target. It's handled by the module itself — the injected module has a `nixos` key, which the target's pipeline processes normally via `compileStatic` → `emit-class`.

### Effect shape

```nix
{
  target = "<ctx-name>" | ["<ctx-name>" ...] | { <ctx-name> = "<entity-name>"; };
  module = <NixOS module or aspect attrset>;
  guard = <optional: targetCtx -> lib.mkIf wrapper>;
  emitterCtx = "<ctx-name>";  # ctx type of the emitting aspect (e.g., "host", "user")
  # Set automatically by the handler from the pipeline's current ctx state.
}
```

The `emitterCtx` field tells `distributeProvideTo` where in the transition graph the emission originated. For sibling routing (target matches emitterCtx), the distributor finds the parent transition's fan-out. For child routing (target is a child of emitterCtx), it follows the emitter's `into.${target}`. Set by the handler, not by the user.

Guards capture source context via Nix closures. The guard function receives the TARGET entity's pipeline ctx (e.g., `{ host = <hostEntity> }`), not the source's. This avoids shadowing: the source `host` is captured in the closure, the target `host` comes from the argument.

`den.provides.to` returns a no-op aspect (`{ includes = []; }`) after emitting the effect. This ensures the `includes` list receives a valid value, not `null`.

### Phase 2 semantics: module injection, not re-resolution

Phase 2 does NOT re-run the aspect pipeline. It injects `provide-to` modules directly into the target's NixOS/homeManager module list — alongside the modules already collected in phase 1. This means:

- Injected modules are plain NixOS/HM modules, not den aspects. They can't use parametric args, constraints, or `includes`.
- Phase 1 pipeline state (constraints, pathSet, chain) is final. Phase 2 doesn't touch it.
- Guard functions produce `lib.mkIf` wrappers applied to the injected module at injection time (during `distributeProvideTo`). The guard receives the target's pipeline ctx (e.g., `{ host = <hostEntity>; }`) — entity objects with `.name`, `.meta`, etc.
- Cost: zero pipeline runs in phase 2. Only module list concatenation + guard evaluation.

For the common case (no cross-entity contributions), phase 2 is a no-op. The orchestration layer checks `state.provideTo null == []` and skips distribution entirely.

For the forward mechanism (existing), performance should improve: the fresh pipeline run in `forward.nix` is eliminated. The source resolution already happens in phase 1, and the forward result is just a module transformation (no pipeline overhead).

### Cycle prevention

- Phase 1 completes fully before phase 2 begins
- Phase 2 pipeline runs do NOT install `provideToHandler`
- No resolution result from phase 1 is required to START phase 2 — only the collected `provideTo` state (a list of emission records)
- Guard functions are closures over phase 1 data — they don't trigger new resolution

## Architecture

### New components

| Component | Location | Purpose |
|---|---|---|
| `provideToHandler` | `handlers/provide-to.nix` | Collects `provide-to` emissions in state |
| `distributeProvideTo` | `pipeline.nix` or new `orchestrate.nix` | Groups emissions by target, injects into target pipelines |
| `den.provides.to` | `modules/aspects/provides/` | Sugar: `den.provides.to "<ctx>" { guard?; module; }` — emits graph-routed `provide-to` |

### Pipeline state additions

```nix
defaultState = {
  # ... existing ...
  provideTo = _: [];  # Thunk chain (same as imports/deferredIncludes)
};
```

### Pipeline API change

`fxFullResolve` already returns `{ value, state }`. The `state.provideTo` field is new but follows the existing pattern (`state.imports`, `state.deferredIncludes`). Callers that only use `fxResolve` (which extracts `state.imports null`) are unaffected.

### Orchestration changes

`osConfigurations.nix` currently:
1. Defines `into.flake-os = { system }: map (host: { host }) hosts`
2. Defines `provides.flake-os = _: osFwd` where osFwd calls `forward.nix`

With provide-to:
1. Same transition definition (unchanged)
2. `osFwd` emits `provide-to` for the forward result instead of returning class keys directly
3. New: after all hosts resolve, `osConfigurations.nix` collects `provideTo` from the pipeline state and injects fleet/cross-host emissions into target host configs

The orchestration change is the largest implementation piece. It requires `osConfigurations.nix` to have access to the full pipeline result (not just the module system output), which means it may need to use `fxFullResolve` instead of going through the transition handler.

### Migration path

1. Add `provideToHandler` to `defaultHandlers` in `pipeline.nix`
2. Add `distributeProvideTo` orchestration function
3. Refactor `osConfigurations.nix` to call `distributeProvideTo` after host resolution
4. Migrate `forward.nix` to emit `provide-to` for the transformed module
5. Add `den.provides.to` sugar and cross-host test

Note: the existing `provides.to-users` / `provides.to-hosts` pattern (`mutual-provider.nix`) is left as-is. It operates within the host-user mutual pipeline and has 30+ usages. `provide-to` is for cross-entity forwarding that mutual-provider cannot handle (sibling hosts, cross-subtree targeting). A future migration could unify them, but it's not in scope here.

### What this does NOT change

- The trampoline (`nix-effects`) — no changes needed
- The core effect handlers (constantHandler, classCollector, chainHandler, etc.)
- The `aspectToEffect` / `compileStatic` compilation
- Single-entity resolution (only multi-entity orchestration changes)
- The `intoCtxType` merge or transition handler internals

## Test: Cross-host `/etc/hosts` generation

```nix
# Cross-host fleet forwarding: each host contributes its entry to all other hosts' /etc/hosts.
# Uses den-level entity metadata (host.meta.ip) — NOT resolved NixOS config values.
test-fleet-etc-hosts = denTest ({ den, lib, igloo, iceberg, ... }: {
  den.hosts.x86_64-linux.igloo.users.tux = {};
  den.hosts.x86_64-linux.iceberg.users.tux = {};

  # IP addresses as den-level metadata on the host entity
  den.hosts.x86_64-linux.igloo.meta.ip = "10.0.0.1";
  den.hosts.x86_64-linux.iceberg.meta.ip = "10.0.0.2";

  # Fleet aspect: each host publishes its IP to sibling hosts
  den.aspects.fleet-hosts.includes = [
    ({ host, ... }:
      den.provides.to "host" {  # "host" from a host aspect = sibling hosts
        guard = targetCtx: lib.mkIf (targetCtx.host.name != host.name);
        module = { networking.extraHosts = "${host.meta.ip} ${host.name}"; };
      }
    )
  ];

  den.aspects.igloo.includes = [ den.aspects.fleet-hosts ];
  den.aspects.iceberg.includes = [ den.aspects.fleet-hosts ];

  expr = {
    igloo-hosts = igloo.networking.extraHosts;
    iceberg-hosts = iceberg.networking.extraHosts;
  };
  expected = {
    igloo-hosts = "10.0.0.2 iceberg";
    iceberg-hosts = "10.0.0.1 igloo";
  };
});
```

The test uses `host.meta.ip` — den entity metadata available before any NixOS resolution. No fixpoint risk: the provide-to closure captures the source host's entity data, and the target's pipeline doesn't depend on the source's resolution.

## Success criteria

- Cross-host forwarding works (fleet `/etc/hosts` test passes)
- `forward.nix` migration: forward results distributed via `provide-to` instead of fresh pipeline runs
- No performance regression for configs without cross-entity contributions
