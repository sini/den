# Relationship Policies and Cross-Entity Resolution

## Problem

Three coupled problems in den's context transition system:

1. **Hardcoded transition topology**: `into` functions on ctx nodes (`den.ctx.host.into.user`) couple topology to entity type definitions. Adding new entity types (kubernetes clusters, environments) requires new ctx nodes with custom wiring.

2. **`__functor` on submodule-evaluated attrsets**: ctx nodes need to be callable for `den.ctx.host { host = config; }`. The `__functor` causes `lib.isFunction` probing issues during NixOS module loading — forcing evaluation chains that reach `config.den` before it's available.

3. **No cross-entity module routing**: the pipeline resolves aspects in isolated scopes. Context flows down (parent to child) but not across entity boundaries. Host A can't contribute modules to host B's config (fleet `/etc/hosts`, haproxy backends). The forward mechanism starts fresh pipeline runs that lose parent context.

## Design

### Three layers

**Layer 1 — Relationship policies** (module evaluation time): declare what relates to what as first-class data, separate from entity definitions.

**Layer 2 — Effect-based materialization** (pipeline execution time): policies compile into per-relationship named effect handlers. The transition handler sends effects and handlers respond with fan-out targets.

**Layer 3 — Cross-entity routing** (orchestration time): when a relationship targets a sibling entity (same type as emitter), resolved modules are collected via `provide-to` effects and distributed to target configs in a second phase.

### Entity types

Unchanged. Typed records with schema: `den.hosts`, `den.users`, `den.homes`, etc. Entity types define *structure* (fields, options). Relationships define *topology* — separate from structure.

---

## Layer 1: Relationship Policies

### Policy declaration

A policy declares a named relationship between entity kinds:

```nix
den.relationships.host-to-users = {
  from = "host";
  to = "user";
  resolve = { host }: map (user: { inherit host user; }) (lib.attrValues host.users);
};

den.relationships.host-wheel-users = {
  from = "host";
  to = "user";
  resolve = { host }:
    builtins.filter
      (user: builtins.elem "wheel" (user.groups or []))
      (lib.attrValues host.users);
};
```

### Resolve function input contract

The `resolve` function receives the **accumulated pipeline context** — the same attrset that parametric aspects receive via `bind.fn`. At host level: `{ host }`. At user level: `{ host, user }`. Each relationship that fans out adds its target entity to the context for downstream relationships.

Additional entities not in the pipeline context (e.g., `environment` in the ACL case) are accessed via module config at registry time — the resolve function is defined in a NixOS module where `config.environments` etc. are available as closures.

The function returns a **list of context attrsets**, each representing one target entity's context:

```nix
resolve = { host }: map (user: { inherit host user; }) (lib.attrValues host.users);
```

Multiple policies can share the same `from`/`to` pair.

### Execution semantics

**Depth-based ordering**: policies run at the depth determined by their `from` type in the entity graph. `environment-to-hosts` runs before `host-to-users` because the environment→host fan-out creates the host-level context that host-level policies consume. This ordering is implicit from the relationship graph, not declared.

**Same-depth independence**: policies sharing the same `from` type at the same pipeline depth execute independently. Each sees the same input context. No sequential dependencies between them. Their results are unioned — all targets from all same-depth policies are resolved.

**Dedup** operates at two layers:
- **Transition-level**: `ctx-seen` deduplicates by transition path key (same as today). Prevents re-entering the same context node via the same path. Two different policies targeting the same entity via different paths are NOT deduped at this layer — both resolve independently.
- **Module-level**: the class collector deduplicates emitted modules by `loc` key (`class@aspectIdentity`). Static aspects reaching the same entity via different paths produce identical `loc` keys → kept once. Parametric aspects with different `__ctxId` are kept separately.
- **Provide-to**: phase 2 module injection tags each module with the *source entity identity* as part of the NixOS module key: `class@aspectIdentity/sourceEntity→targetEntity`. This ensures multiple sources providing the same capability to the same target don't conflict — `nixos@webserver/{web1}→{lb}` and `nixos@webserver/{web2}→{lb}` are distinct keys, both kept. Same source + same aspect + same target deduplicates.

**Diamond resolution**: when the same entity is reachable via multiple paths (A→B→X and A→C→X), each path produces an independent resolution run. The class collector deduplicates by aspect identity + class key — identical aspects reaching the same entity via different paths produce the same dedup key and are kept once. Different aspects or parametric aspects with different contexts (`__ctxId`) are kept separately and NixOS module merge resolves any conflicts.

**Conflict resolution**: policies are pure queries — they produce targets, not modules. Conflicts can only arise in the *modules* emitted for those targets. Since modules are injected into NixOS/homeManager evaluation, the standard NixOS module priority system handles conflicts. No custom conflict resolution needed at the policy level.

**Ordering**: policies at the same depth execute in declaration order for determinism, but correctness must not depend on order.

**Context key collisions**: the `as` field determines the context key name for the target entity. Two policies with the same `as` value targeting the same pipeline depth would collide — the last-evaluated overwrites. Policies with unique `as` values (or distinct `to` types) avoid this. Collisions should emit a trace warning.

**Entity identity**: dedup and tracing require a consistent identity for each entity. Built-in types use `entity.name`. Custom entity types should provide an identity derivation (e.g., via a `name` field or a policy-level `identity` function). Entities without a `name` field use a hash of the context attrset as fallback.

**Error handling**: if `resolve` returns a non-list, emit a trace warning and produce no fan-out. Empty list produces no fan-out silently. Missing entity types (typo in `from`/`to`) produce a warning at pipeline entry.

### Inline sugar on ctx nodes

Ctx nodes can declare relationships inline via `into`. Key names map to entity types:

```nix
den.ctx.host.into = {
  user = { host }: map (user: { inherit host user; }) (lib.attrValues host.users);
  default = lib.singleton;
};
```

Each key desugars to an anonymous policy:

```nix
# den.ctx.host.into.user = fn  →
{ from = "host"; to = "user"; resolve = fn; }
```

### Activation model

Policies are *available* when their module is imported (from den batteries or external flakes) but *active* only when enabled. Same pattern as den batteries (`den.provides.mutual-provider`).

**Four activation levels:**

```nix
# 1. Den core — fundamental relationships, always active.
#    Defined in modules/context/host.nix etc., users don't touch these.
#    (host→user, host→default, user→default, user→home chain)

# 2. den.default.relationships — cross-cutting, user opt-in.
#    Applies to all contexts.
den.default.relationships = [
  den.relationships.host-to-users
  den.relationships.mutual-provider
];

# 3. den.ctx.<kind>.relationships — scoped to entity kind, user opt-in.
#    Applies when resolving any entity of that kind.
den.ctx.host.relationships = [
  den.relationships.host-to-peers
];

# 4. Entity instance — scoped to a specific entity.
#    Applies only when resolving this particular host/user/etc.
den.hosts.x86_64-linux.igloo.relationships = [
  den.relationships.host-to-peers
];
```

**Battery pattern:** a battery module defines the policy in `den.relationships.*` (available). The user enables it via `den.default.relationships` or `den.ctx.<kind>.relationships` (active). Same as `den.ctx.user.includes = [ den.provides.mutual-provider ]` today.

**External flakes:** an external flake can provide policies in its flake module. The user imports the flake and enables its policies — no implicit activation from imports.

### Formal vs inline

**Formal** (`den.relationships.*`) for: reusable patterns, bidirectional relationships, cross-cutting concerns (ACL), custom entity types.

**Inline** (`den.ctx.*.into`) for: simple one-off transitions, quick prototyping. Inline declarations are always active on their ctx node (backwards compat with current `into`).

Both compile to the same effect handlers.

---

## Layer 2: Effect-Based Materialization

### Handler installation

At pipeline entry, all policies are compiled into per-relationship effect handlers and installed via `scope.provide`:

```nix
handlers."host-to-users" = { param, state }:
  let targets = policy.resolve param.context;
  in { resume = targets; inherit state; };
```

### Transition dispatch

The transition handler sends per-relationship named effects instead of reading `into`:

```nix
# Before (reads into data):
intoResult = aspect.into currentCtx;
transitions = flattenInto intoResult [];

# After (sends per-relationship effects):
fx.send "host-to-users" { host = currentHost; }
# handler responds with [{ host, user = tux }, { host, user = alice }, ...]
```

### Routing decision

The transition handler determines routing based on the relationship's target entity type relative to the current scope:

| Target type vs current scope | Routing | Mechanism |
|---|---|---|
| **Child** (different type, resolves within current pipeline) | Resolve locally | Tag with `__scopeHandlers`, call `aspectToEffect` |
| **Sibling** (same type as emitter, needs separate pipeline) | Collect for phase 2 | Emit `provide-to` effect (Layer 3) |

One handler per relationship — traces show exactly which fired.

### ctxApply dissolves

`den.ctx.host { host = config; }` is replaced by explicit pipeline entry:

```nix
# Before:
den.lib.aspects.resolve "flake" (den.ctx.flake { })

# After:
den.lib.aspects.resolve "flake" {
  entity = den.ctx.flake;
  context = { };
  relationships = applicablePolicies;
}
```

No `__functor` on any submodule-evaluated attrset.

---

## Layer 3: Cross-Entity Routing (provide-to)

### The problem

When a relationship targets a sibling entity (host→peer, where peer is another host), the resolved modules must land in the *peer's* config, not the current host's. The current pipeline's `emit-class` always goes to the root classCollector for the *current* pipeline run.

### Two-phase resolution

**Phase 1 — Normal resolution with cross-entity collection**: the pipeline runs normally. When the transition handler detects a sibling target (same entity type as emitter), it collects resolved modules in `state.provideTo` instead of emitting to the current classCollector:

```nix
provideToHandler = {
  "provide-to" = { param, state }: {
    resume = null;
    state = state // {
      provideTo = _: ((state.provideTo or (_: [])) null) ++ [param];
    };
  };
};
```

**Phase 2 — Distribution at orchestration level**: after phase 1 completes, the orchestration layer reads `state.provideTo null`, groups emissions by target entity, and injects them as additional modules when building target configs:

```
flake
  → flake-system (per system)
    → flake-os (per host)         # Phase 1: resolve each host, collect provide-to
    → distribute provide-to       # Phase 2: group by target, inject into targets
    → build target configs        # Targets receive injected modules
```

### Cycle prevention

- Phase 1 completes fully before phase 2 begins
- Phase 2 pipeline runs do NOT install `provideToHandler`
- Injected modules cannot emit further `provide-to` — prevents cycles structurally

### Phase 2 semantics

Phase 2 does NOT re-run the aspect pipeline. It injects `provide-to` modules directly into the target's module list — alongside modules from phase 1. Injected modules are dendritic (have class keys). Zero pipeline runs in phase 2 — only module list concatenation.

For configs without cross-entity contributions, phase 2 is a no-op.

### Effect shape

```nix
{
  target = "<entity-kind>" | ["<kind>" ...];  # single or multi-hop
  content = <aspect attrset with dendritic class keys>;
  emitterCtx = "<entity-kind>";  # set by handler, not user
}
```

Multi-hop targets walk the relationship graph, fanning out at each step.

### Forward mechanism migration

`forward.nix` currently starts fresh `den.lib.aspects.resolve` calls, losing parent context. With provide-to:
- Source class resolution stays in phase 1
- mapModule/guards/adapters stay in phase 1
- The final result emits `provide-to` instead of being returned directly
- The orchestration layer injects it into the target

The adapter/guard/mapModule machinery stays intact. Only routing changes.

---

## Examples

### Kubernetes cluster

```nix
den.relationships.cluster-to-nodes = {
  from = "cluster";
  to = "node";
  resolve = { cluster }: cluster.nodes;
};

den.relationships.cluster-to-services = {
  from = "cluster";
  to = "service";
  resolve = { cluster }: lib.attrValues cluster.services;
};

den.relationships.service-to-storage = {
  from = "service";
  to = "node";
  resolve = { service, cluster }:
    builtins.filter
      (node: builtins.any (t: t == service.storageClass) (node.taints or []))
      cluster.nodes;
};
```

### ACL resolution (end-to-end)

This example shows a full relationship chain: environment → host → user, where each step adds its entity to the pipeline context for downstream policies.

**Entity type declarations:**

```nix
# Typed records — structure only, no topology
den.environments.prod = {
  system-access-groups = [ "system-access" ];
  access.sini = [ "admins" "wheel" "system-access" ];
  access.json = [ "admins" ];  # admin but no login
};

# Hosts declare their environment. Structure, not topology.
den.hosts.x86_64-linux.cortex = {
  environment = "prod";
  system-access-groups = [ "workstation-access" ];
  users.sini = {};
  users.json = {};
};

den.groups = {
  system-access = { scope = "system"; };
  workstation-access = { scope = "system"; members = [ "system-access" ]; };
  admins = { scope = "kanidm"; };
  wheel = { scope = "unix"; };
};
```

**Relationship policy declarations:**

```nix
# Step 1: environment fans out to its hosts.
# The policy queries all hosts whose environment field matches.
den.relationships.environment-to-hosts = {
  from = "environment";
  to = "host";
  resolve = { environment }:
    let
      allHosts = lib.concatMap lib.attrValues (lib.attrValues den.hosts);
    in
    map (host: { inherit environment host; })
      (builtins.filter (h: h.environment == environment.name) allHosts);
};

# Step 2: host fans out to qualified users
# Because environment-to-hosts ran first, { environment } is in the context
den.relationships.host-login-users = {
  from = "host";
  to = "user";
  resolve = { host, environment }:
    let
      gates = lib.unique (
        (environment.system-access-groups or [])
        ++ (host.system-access-groups or [])
      );
      qualifies = username:
        let
          direct = environment.access.${username} or [];
          resolved = transitiveMembers den.groups direct;
          systemScoped = builtins.filter
            (g: (den.groups.${g}.scope or "") == "system")
            resolved;
        in
        builtins.any (g: builtins.elem g gates) systemScoped;
      qualifiedNames = builtins.filter qualifies
        (builtins.attrNames host.users);
    in
    map (name: { inherit environment host; user = host.users.${name}; })
      qualifiedNames;
};
```

**Pipeline context accumulation:**

```
entry: { environment = prod }
  ↓ environment-to-hosts
  { environment = prod, host = cortex }
    ↓ host-login-users
    { environment = prod, host = cortex, user = sini }  ← qualifies (has system-access)
    # json does NOT appear — no system-scoped group intersects gates
```

Each relationship adds its `to` entity to the context. Downstream policies see the full accumulated context via `bind.fn` resolution — same mechanism as parametric aspects.

### Cross-host fleet `/etc/hosts`

```nix
# Peer relationship: each host fans out to sibling hosts.
# to = "host" (same type as emitter) triggers provide-to routing.
# The context key is "peer" — an alias for the target entity in this
# relationship. The routing decision uses the `to` declaration ("host"),
# not the context key name.
den.relationships.host-to-peers = {
  from = "host";
  to = "host";
  as = "peer";  # context key name (default: same as `to`)
  resolve = { host }:
    map (peer: { inherit peer; })
      (filter (h: h.name != host.name) (attrValues den.hosts.${host.system}));
};

# Aspect: each host publishes its IP to peers via parametric include.
# The { peer } arg is resolved via the host-to-peers relationship.
# Because peer is a sibling host, the transition handler routes this
# through provide-to — the resolved nixos module lands in the peer's config.
den.aspects.fleet-hosts = { host, ... }: {
  includes = [
    ({ peer, ... }: {
      nixos.networking.extraHosts = "${host.meta.ip} ${host.name}";
    })
  ];
};

# Result: igloo gets "10.0.0.2 iceberg", iceberg gets "10.0.0.1 igloo"
```

Note: both examples use entity metadata (`host.meta.ip`), not resolved NixOS config. No fixpoint risk — provide-to closures capture source entity data.

### Cross-host haproxy backend registration

```nix
den.aspects.webserver = { host, ... }: {
  nixos.services.nginx.enable = true;

  # Regular parametric include — { peer } resolved via host-to-peers
  includes = [
    ({ peer, ... }:
      lib.optionalAttrs (peer.hasAspect den.aspects.loadbalancer) {
        nixos.services.haproxy.frontends.app.backends = [
          { address = host.meta.ip; port = 8080; }
        ];
      }
    )
  ];
};
```

---

## Backwards compatibility

**`den.ctx.host.into.user = fn`** → shim: desugars to anonymous relationship policy. `intoCtxType` merge semantics preserved.

**`den.hosts.x86_64-linux.igloo.users.tux = {}`** → unchanged: `users` stays as structure. The `host-to-users` policy reads it.

**`den.ctx.host { host = config; }`** → migration: `den.lib.applyCtx` function provides same behavior without `__functor`.

**`provides.to-users` / `provides.to-hosts`** (mutual-provider.nix) → left as-is initially. Operates within host-user mutual pipeline. A future migration could unify with provide-to.

---

## What stays

- Entity types and schema (`den.hosts`, `den.users`, `den.homes`)
- `den.ctx` namespace for inline relationship sugar
- `den.aspects` for aspect definitions
- `den.schema.*` for validation
- The fx pipeline and effects system
- `__scopeHandlers` for context propagation
- `__fn`/`__args` parametric type for pipeline wrappers

## What changes

- `into` on ctx nodes → shim over relationship policy registration
- `ctxApply` → internal mechanism, not user-facing functor
- `__functor` on ctxSubmodule → removed
- Transition handler → sends per-relationship named effects
- Transition handler → routing decision (child vs sibling)
- Pipeline entry → explicit relationship handler installation
- `forward.nix` → emits `provide-to` instead of fresh pipeline runs

## What's new

- `den.relationships` option for formal policy declarations
- `den.default.relationships` for cross-cutting policy activation
- `den.ctx.<kind>.relationships` for scoped policy activation
- Per-relationship effect handlers
- `provideToHandler` for cross-entity collection
- `distributeProvideTo` orchestration function
- `den.lib.applyCtx` function (replaces functor call syntax)

## Constraints

**No config references in provide-to closures.** Source entities must capture entity metadata (e.g., `host.meta.ip`), not evaluated NixOS config (e.g., `config.networking.hostName`). This prevents fixpoint evaluation between source and target configs. Violation of this constraint causes infinite recursion. This is intentional — `provide-to` is a one-way push mechanism, not a bidirectional fixed-point like NixOps' `nodes.*` references.

**Phase 2 module injection ordering.** Modules injected via provide-to are appended to the target's module list after locally-resolved modules. Ordering between provide-to sources follows the source entity's pipeline evaluation order (deterministic but arbitrary). Module correctness must not depend on injection order — use NixOS priorities (`mkDefault`, `mkForce`) if ordering matters.

## Observability

**Trace output**: one trace per relationship handler fired, showing policy name and target count. Existing pipeline traces (compileStatic, classCollector, includeHandler) are unaffected.

**Inspection utility**: `den.lib.relationships.inspect` — given an entity kind and context, returns all applicable policies and their resolved targets without running the full pipeline. Cheap (just calls `resolve` functions). Essential for debugging "why did host X get this module?"

```nix
# Debug: what relationships fire for igloo?
den.lib.relationships.inspect {
  kind = "host";
  context = { host = den.hosts.x86_64-linux.igloo; };
}
# → { host-to-users = [{ host, user = tux }, ...]; host-to-peers = [...]; }
```

## Future work

- **Policy composition operators** (union, intersection, difference) — not needed now but possible extension
- **Target-side opt-out** — entity declares `meta.relationshipExclusions` to refuse targeting by specific policies
- **Memoization guidance** for expensive `resolve` functions (compute mapping once at module eval time)
- **Bidirectional config access** — `provide-to` is one-way push; pulling target config requires fixed-point evaluation (NixOps model) which is explicitly out of scope

## What does NOT change

- The nix-effects trampoline — no changes needed
- Core effect handlers (constantHandler, classCollector, chainHandler, constraintRegistry)
- `aspectToEffect` / `compileStatic` compilation
- Single-entity resolution (only multi-entity orchestration changes)
- The `__ctxId` / `__parametricResolved` identity/dedup mechanism

## Rejected alternatives

### Inherited context chain

Thread parent context into child pipeline runs via an `inheritCtx` parameter. Simpler, but cycles are prevented by API discipline rather than by construction. Doesn't generalize to sibling-to-sibling forwarding.

### Simpler ctx threading

Fix `__parentCtx` propagation without new effects. Doesn't address cross-entity use case. The scope.provide migration subsumes this for parent-to-child propagation.

## Pipeline state additions

```nix
defaultState = {
  # ... existing (imports, pathSet, constraintRegistry, etc.) ...
  provideTo = _: [];  # Thunk chain — same pattern as imports
};
```

The thunk wrapping (`_: [...] ++ [param]`) prevents `deepSeq` from forcing aspect content that may reference lazy option defaults. `state.provideTo null` unwraps the chain.

## Implementation components

| Component | Location | Purpose |
|---|---|---|
| Relationship option type | `nix/lib/relationship-types.nix` (new) | Policy schema, registration |
| Relationship module | `nix/nixModule/relationships.nix` (new) | `den.relationships` option |
| Per-relationship handlers | `nix/lib/aspects/fx/handlers/relationship.nix` (new) | Compile policies → handlers |
| `provideToHandler` | `nix/lib/aspects/fx/handlers/provide-to.nix` (new) | Cross-entity state collection |
| `transitionHandler` changes | `nix/lib/aspects/fx/handlers/transition.nix` | Routing decision (child vs sibling) |
| `distributeProvideTo` | `nix/lib/aspects/fx/pipeline.nix` or new | Phase 2 orchestration |
| Orchestration changes | `modules/outputs/osConfigurations.nix` | Phase 2 distribution after host resolution |
| Forward migration | `nix/lib/forward.nix` | Emit provide-to instead of fresh pipeline |

## Migration path

1. Add `den.relationships` option type and module
2. Implement per-relationship effect handlers
3. Shim `den.ctx.*.into` to register policies
4. Update transition handler for effect-based dispatch + routing decision
5. Add `provideToHandler` to `defaultHandlers`
6. Add `distributeProvideTo` orchestration function
7. Refactor `osConfigurations.nix` for phase 2 distribution
8. Remove `__functor` from ctxSubmodule, update call sites to `den.lib.applyCtx`
9. Migrate `forward.nix` to emit provide-to
10. Add cross-entity tests (fleet, haproxy)

## Success criteria

- All existing tests pass (zero regressions)
- Relationship policies express current host→user→home transitions
- Cross-entity forwarding works (fleet `/etc/hosts`, haproxy backend tests)
- `forward.nix` migration: results distributed via provide-to
- No `__functor` on any submodule-evaluated attrset
- No performance regression for configs without cross-entity contributions

## scope.provide vs scope.stateful

The pipeline uses `scope.provide` (not `scope.stateful`) for installing context handlers. The distinction matters:

- `scope.stateful` does state fork-join via `state.update`. Inner state overwrites outer state — class collector mutations are lost (79% event drop observed in testing).
- `scope.provide` installs handlers via `rotate` with state-discarding return. Rotated effects modify outer state directly. No state overwrite.
- `scope.run` discards inner state entirely. Equivalent to `scope.provide` mechanically but signals "isolated execution" not "augment handlers."

The pipeline needs `scope.provide` because constantHandler bindings are stateless (resume with constant, pass state through) while emit-class/emit-include effects that rotate outward must modify the shared root state.

## Pre-work completed

- `scope.provide` migration: all `scope.stateful` calls in aspect.nix, transition.nix, ctx-apply.nix replaced with `scope.provide` (commits `2b3ac91a`, `c9b428a4`)
- Parametric type separation: `__fn`/`__args` replace `__functor`/`__functionArgs` on pipeline wrappers
- `__scope`/`__parentScope` removal: derive from `__scopeHandlers` at point of use
- `resolvedCtx` removal: parametric shims stamp `__scopeHandlers` directly via `constantHandler`

---

## TL;DR

**Entity types** (host, user, cluster) define structure. **Relationship policies** define topology — how entities connect. Policies are first-class data in `den.relationships`, activated via `den.default.relationships` or scoped to a kind/instance.

At pipeline time, policies compile into **per-relationship named effect handlers**. The transition handler sends `"host-to-users"` instead of reading `into` data. One handler per relationship = clear traces.

When a relationship targets a **sibling entity** (same type as emitter, e.g., host→peer-host), resolved modules route through a **two-phase provide-to mechanism**: phase 1 collects, phase 2 distributes to target configs. No fixed-point — source captures entity metadata, not evaluated config.

`__functor` is removed from all submodule-evaluated attrsets. `ctxApply` becomes an internal function. The current `into`/`ctxApply`/`forward` interfaces become shims over the new system.
