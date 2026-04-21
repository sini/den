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

**Independence**: policies with the same `from` type execute independently. Each sees the same input context. No sequential dependencies.

**Dedup**: each relationship has its own dedup namespace, keyed by policy name + target entity identity.

**Ordering**: policies execute in declaration order for determinism, but correctness must not depend on order.

**Error handling**: if `resolve` returns a non-list or empty list, no fan-out (no error). Missing entity types produce a warning at pipeline entry.

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

### Formal vs inline

**Formal** (`den.relationships.*`) for: reusable patterns, bidirectional relationships, cross-cutting concerns (ACL), custom entity types.

**Inline** (`den.ctx.*.into`) for: simple one-off transitions, quick prototyping.

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

### ACL resolution

```nix
den.relationships.host-login-users = {
  from = "host";
  to = "user";
  resolve = { host, environment }:
    let
      gates = lib.unique (
        (environment.system-access-groups or [])
        ++ (host.system-access-groups or [])
      );
      resolveGroups = user:
        let direct = environment.access.${user.name} or [];
        in transitiveMembers groups direct;
      qualifies = user:
        let resolved = resolveGroups user;
            systemScoped = builtins.filter (g: (groups.${g}.scope or "") == "system") resolved;
        in builtins.any (g: builtins.elem g gates) systemScoped;
    in
    builtins.filter qualifies (lib.attrValues environment.users);
};
```

### Cross-host fleet `/etc/hosts`

```nix
# Peer relationship: each host fans out to sibling hosts
den.relationships.host-to-peers = {
  from = "host";
  to = "host";  # same type = sibling = provide-to routing
  resolve = { host }:
    map (h: { peer = h; })
      (filter (h: h.name != host.name) (attrValues den.hosts.${host.system}));
};

# Cross-provider: each host publishes its IP to peers
den.ctx.host.provides.peer = { host }: { peer }: {
  nixos.networking.extraHosts = "${host.meta.ip} ${host.name}";
};

# Result: igloo gets "10.0.0.2 iceberg", iceberg gets "10.0.0.1 igloo"
```

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
- Per-relationship effect handlers
- `provideToHandler` for cross-entity collection
- `distributeProvideTo` orchestration function
- `den.lib.applyCtx` function (replaces functor call syntax)

## Pre-work completed

- `scope.provide` migration (replaces `scope.stateful` for reader/val bindings)
- Parametric type separation (`__fn`/`__args` replace `__functor`/`__functionArgs` on wrappers)
- `__scope`/`__parentScope` removal (derive from `__scopeHandlers`)
- `resolvedCtx` removal (parametric shims stamp `__scopeHandlers` directly)
