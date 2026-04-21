# Relationship Policies: Generalized Entity Transitions

## Problem

Context transitions in den are hardcoded as `into` functions on ctx nodes (`den.ctx.host.into.user`). This couples the transition topology to specific entity types and requires ctx nodes to be callable via `__functor` — causing lazy evaluation issues with `lib.isFunction` probing during NixOS module loading.

The `into` mechanism also only supports one direction: host declares its users. But real-world relationships are richer — users could declare which hosts they belong to, a kubernetes cluster relates to both nodes and services, and access control (ACL) requires predicate-based queries like "users whose groups contain wheel."

## Design

### Two phases

**Registry building** (module evaluation time): relationship policies are declared as pure functions with access to the entity registry. This defines *what relates to what*.

**Materialization** (pipeline execution time): policies compile into per-relationship effect handlers installed on the fx pipeline. The transition handler sends named effects and handlers respond with fan-out targets.

### Entity types

Unchanged. Typed records with schema: `den.hosts`, `den.users`, `den.homes`, etc. Entity types define *structure* (fields, options). Relationships define *topology* (how entities connect) — separate from structure.

### Relationship policies

A policy declares a named relationship between entity kinds:

```nix
den.relationships.host-to-users = {
  from = "host";
  to = "user";
  resolve = { host }: lib.attrValues host.users;
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
# Returns list of { host, user } contexts — one per user on this host
resolve = { host }: map (user: { inherit host user; }) (lib.attrValues host.users);
```

Multiple policies can share the same `from`/`to` pair — they represent different relationships between the same entity kinds.

### Execution semantics

**Independence**: policies with the same `from` type execute independently. Each sees the same input context. No sequential dependencies — a policy cannot depend on another policy's output.

**Dedup**: each relationship has its own dedup namespace, keyed by policy name + target entity identity. Two policies targeting the same entity kind don't interfere with each other's dedup.

**Ordering**: policies execute in declaration order for determinism, but correctness must not depend on order (since they're independent).

**Error handling**: if `resolve` returns a non-list or an empty list, the relationship produces no fan-out (no error). Missing entity types (typo in `from`/`to`) should produce a warning at pipeline entry when handlers are installed.

### Inline sugar on ctx nodes

Ctx nodes can declare relationships inline. Unlike bare functions, inline declarations must specify `to` explicitly to avoid ambiguous type inference:

```nix
den.ctx.host.into = {
  user = { host }: map (user: { inherit host user; }) (lib.attrValues host.users);
  default = lib.singleton;
};
```

Each key in `into` desugars to an anonymous relationship policy:

```nix
# den.ctx.host.into.user = fn  desugars to:
{ from = "host"; to = "user"; resolve = fn; }
```

The `into` key names (`user`, `default`) map to entity types. This preserves the current `den.ctx` interface while the underlying mechanism is generalized.

### Pipeline execution

**Handler installation**: at pipeline entry (`fxResolveTree` or its replacement), all registered policies are compiled into per-relationship effect handlers and installed via `scope.provide`. The pipeline collects policies from both `den.relationships` (formal) and desugared `den.ctx.*.into` (inline).

```nix
# For each policy:
handlers."host-to-users" = { param, state }:
  let targets = policy.resolve param.context;
  in { resume = targets; inherit state; };
```

**Transition dispatch**: the transition handler sends per-relationship named effects instead of reading `into` data. It iterates the response (list of target contexts) and recurses into each:

```nix
# Before (reads into data):
intoResult = aspect.into currentCtx;
transitions = flattenInto intoResult [];

# After (sends per-relationship effects):
fx.send "host-to-users" { host = currentHost; }
# handler responds with [{ host, user = tux }, { host, user = alice }, ...]
# transition handler recurses into each
```

**Handler responsibilities**: the effect handler returns raw target contexts (list of attrsets). The transition handler is responsible for tagging each target with `__scopeHandlers`, looking up the target entity's aspects (via `provides` or aspect registry), and calling `aspectToEffect`. This keeps handlers simple (pure query) and the transition handler generic (same iteration logic for all relationships).

One handler per relationship. Traces show exactly which relationship fired: `host-to-users`, `cluster-to-services`.

### ctxApply dissolves

The `den.ctx.host { host = config; }` functor call pattern is replaced by an explicit pipeline entry:

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

No `__functor` on any submodule-evaluated attrset. The `ctxApply` function becomes the internal mechanism that the pipeline entry calls — not a user-facing functor.

### Backwards compatibility

The current interfaces become shims:

**`den.ctx.host.into.user = fn`** — the `into` option desugars to relationship policy registration. The `intoCtxType` merge semantics are preserved in the shim.

**`den.hosts.x86_64-linux.igloo.users.tux = {}`** — the `users` option on host type stays as structure. The host-to-users relationship policy reads it.

**`den.ctx.host { host = config; }`** — if the functor interface is needed during migration, a `den.lib.applyCtx` function provides the same behavior without `__functor`.

### Formal vs inline policies

**Formal policies** (`den.relationships.*`) for:
- Reusable/shared patterns (host-to-users is used by all hosts)
- Bidirectional relationships (user declares hosts, host declares users)
- Cross-cutting concerns (ACL group-based access gating)
- Custom entity types (kubernetes cluster → services)

**Inline sugar** (ctx node keys) for:
- Simple one-off transitions (host → default context)
- Quick prototyping before formalizing

Both compile to the same effect handlers at pipeline execution time.

### Example: Kubernetes cluster

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

### Example: ACL resolution

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

## What stays

- Entity types and their schema (`den.hosts`, `den.users`, `den.homes`)
- `den.ctx` namespace for inline relationship sugar
- `den.aspects` for aspect definitions
- `den.schema.*` for validation
- The fx pipeline and effects system
- `__scopeHandlers` for context propagation
- `__fn`/`__args` parametric type for pipeline wrappers

## What changes

- `into` option on ctx nodes → shim over relationship policy registration
- `ctxApply` → internal pipeline mechanism, not a user-facing functor
- `__functor` on ctxSubmodule → removed entirely
- Transition handler → sends per-relationship named effects
- Pipeline entry → explicit relationship handler installation

## What's new

- `den.relationships` option for formal policy declarations
- Per-relationship effect handlers
- `den.lib.applyCtx` function (replaces functor call syntax during migration)

## Rationale

Under the current model, the transition topology is embedded in ctx node definitions. Each ctx node carries `into` functions that encode relationships. This creates three problems:

1. **`__functor` on submodule-evaluated attrsets** — ctx nodes need to be callable for the `den.ctx.host { host = config; }` entry point. The `__functor` causes `lib.isFunction` probing issues during NixOS module loading (forcing evaluation chains that reach `config.den` before it's available).

2. **Unidirectional relationships** — `into` on host can express "host has users" but not "user belongs to hosts." Bidirectional relationships require separate mechanisms outside the ctx system.

3. **Fixed entity kind topology** — adding new entity types (kubernetes clusters, environments) requires new ctx node types with custom `into` wiring. The relationship between kinds is implicit in the code, not declarative data.

Relationship policies make topology first-class data, separate from entity types. The effects system handles materialization — the pipeline doesn't know about entity types, it just sends named effects and handlers respond. Custom entity types and complex query-based relationships (ACL group membership) use the same mechanism as simple host-to-users fan-out.
