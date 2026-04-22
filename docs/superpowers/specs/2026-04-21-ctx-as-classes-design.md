# Separating Data, Relationships, and Behavior

**Date:** 2026-04-21 (revised with Vic's feedback)
**Branch:** feat/rm-legacy
**Status:** Draft — pending peer review

## Terminology

Before anything else, align on terms:

| Term | Den concept | Examples |
|------|-------------|----------|
| **Entity** | A tangible thing in the user's infrastructure | A host, a user, a home |
| **Schema** | The data structure defining what an entity IS | `den.schema.host` + `den.schema.base` + hostSubmodule from types.nix |
| **Class** (Nix config class) | A category of behavior/configuration | `nixos`, `darwin`, `homeManager`, custom classes |
| **`den.ctx`** | Deprecated — conflated relationships and behavior. Being fully removed by this spec | `den.ctx.host`, `den.ctx.hm-host`, `den.ctx.default` |
| **Aspect** | A container of behavior (Nix config classes) | `den.aspects.gaming` — defines nixos/darwin/homeManager configs |
| **Relationship** | How entities transition into or relate to each other | host fans out into users, host transitions into hm-host |

**"Class" is reserved for Nix configuration classes (behavior).** Not entity types, not data definitions.

## Problem

`den.ctx` conflates two of the three concerns:

1. **Relationships** — `into.*` transitions define how to move between context stages (`{host}` → `{host, user}`)
2. **Behavior** — each ctx node IS an aspect, so `den.ctx.hm-host.nixos.foo = "bar"` and `den.ctx.default.includes = [z]` work

This conflation exists because the original design needed context-passing between aspect-providers (functions producing collections of Nix classes). `den.ctx` was the mechanism: an aspect augmented with `into.*` transitions. The name "ctx" itself leaks the implementation detail of context-passing from the legacy core.

**What `den.ctx` is NOT:** It is not about entity data types. Entity schemas are defined by schema mixins:
- Host = `den.schema.host` + `den.schema.base` + hostSubmodule (types.nix)
- User = `den.schema.user` + `den.schema.base` + userType (types.nix)
- Home = `den.schema.home` + `den.schema.base` + homeType (types.nix)

The ~24 ctx nodes are not entity type definitions — they are pipeline stages with behavior attached. This is why `hm-host`, `flake-system`, `default` etc. exist as ctx nodes despite not being real-world entities.

### Why this is a problem

Because `den.ctx` is both relationships AND behavior:
- Adding a transition requires creating a full aspect node (even if you only need the `into`)
- Behavior scoped to a relationship stage (e.g., "only apply this nixos config when home-manager is enabled") requires an intermediate ctx node
- Users struggle to understand what `den.ctx` is for — the name describes an implementation detail, not a declarative concept
- The 3-node `makeHomeEnv` chains (`host.into.X-host` → `X-host.into.X-user` → `X-user.provides`) exist solely to thread context through intermediate aspect nodes

## Design: Three Clean Separations

### The Three Concerns

```
Data (Schema)        — what entities ARE       — den.schema.* + entity types
Relationships        — how entities RELATE     — den.relationships (new)
Behavior             — how entities RESOLVE    — den.aspects.* + fx pipeline
```

`den.ctx` is fully removed. Its two roles split cleanly:
- `into.*` transitions → `den.relationships`
- Aspect behavior (`.nixos`, `.includes`, freeform class keys) → `den.aspects` with relationship-scoped activation

### Data: Entity Schemas

Entity schemas define what entities ARE. Currently scattered across `nix/lib/types.nix` (entity submodule types) and `modules/options.nix` (schema entry wiring).

Each entity kind is defined by schema mixins:
```nix
# A host entity is shaped by these three "mixins":
den.schema.host    # user-extensible schema (deferred module)
den.schema.base    # shared across all entity kinds (hasAspect, etc.)
hostSubmodule      # structural options: name, system, class, aspect, users, instantiate, intoAttr
```

Entities are local to a flake — which hosts, users, and homes exist is defined by the consumer. Schemas can be shared via namespaces, but entity instances are always local.

**No change to the schema system itself.** The reorganization consolidates scattered type definitions into entity-per-file structure (see File Reorganization below).

### Relationships: Entity Transitions

Relationships declare how entities transition into each other. This is what `into.*` currently does, extracted into its own system.

**Before (relationship buried in ctx aspect):**
```nix
den.ctx.host.into.user = { host }:
  map (user: { inherit host user; }) (lib.attrValues host.users);
```

**After (relationship as first-class declaration):**
```nix
den.relationships.host-to-users = {
  from = "host";
  to = "user";
  resolve = { host }:
    map (user: { inherit host user; }) (lib.attrValues host.users);
};
```

Relationships must support nesting for namespace reuse. Den is not only about configuring local infrastructure — the denful project will share reusable relationships + behavior via namespaces, organized as a nested tree (like nixpkgs has nested package-sets). `den.relationships` should support the same nested structure that aspects do.

```nix
# Namespace-provided relationships (denful example)
den.ns.desktop.relationships.host-to-display-server = { ... };
den.ns.kubernetes.relationships.cluster-to-nodes = { ... };
```

### Behavior: Aspects and Scoped Activation

Behavior is defined as aspects — containers of Nix configuration classes. This is already clean in Den. `den.aspects.gaming` defines the behavior of the gaming feature.

The key question is: **what happens to behavior that was scoped to relationship stages?**

Currently, `den.ctx.hm-host` is an aspect node that guarantees home-manager is enabled on the host. Users write:
```nix
den.ctx.hm-host.nixos.foo = "bar";        # only applies where HM is enabled
den.ctx.hm-host.includes = [ someAspect ]; # includes scoped to HM hosts
den.ctx.default.nixos.x = "y";            # applies to all entities
den.ctx.default.includes = [ z ];          # includes for everything
```

After removing `den.ctx`, this scoped behavior needs a new home. Two options:

**Option A: Behavior on relationship declarations**
```nix
den.relationships.host-to-hm-host = {
  from = "host";
  to = "hm-host";
  resolve = detectHost { ... };
  # Behavior that activates when this relationship resolves:
  aspects.nixos.foo = "bar";
  aspects.includes = [ someAspect ];
};
```

**Option B: Conditional aspects with relationship predicates**
```nix
den.aspects.hm-host-config = {
  # Only activates when the host-to-hm-host relationship resolved
  meta.when = "host-to-hm-host";
  nixos.foo = "bar";
  includes = [ someAspect ];
};
```

**Option C: Keep intermediate aspects as regular aspects, activated by relationships**

The `hm-host` aspect continues to exist in `den.aspects` (not `den.ctx`). The relationship pipeline activates it when the `host-to-hm-host` transition fires. This is closest to current behavior — the aspect just loses its `into.*` and moves from `den.ctx.hm-host` to `den.aspects.hm-host`.

**Activation mechanism for Option C:** When a relationship resolves (e.g., `host-to-hm-host`), the relationship handler looks up `den.aspects.${target}` (e.g., `den.aspects.hm-host`) and includes it in the resolution scope for that transition. This mirrors what the current `transitionHandler` does when it visits a ctx node — it resolves the node's aspect. The difference is that the aspect no longer carries `into.*`; the relationship handler drives the traversal and the aspect just provides behavior.

Concretely, a relationship declaration can reference a target aspect:
```nix
den.relationships.host-to-hm-host = {
  from = "host";
  to = "hm-host";
  resolve = detectHost { ... };
  aspect = "hm-host";  # activates den.aspects.hm-host when this transition fires
};
```

**Recommendation:** Option C for migration simplicity. The intermediate aspects already work; they just need to stop being the place where relationships are declared. Moving them from `den.ctx` to `den.aspects` is a rename, not a redesign.

### The `default` Stage

`default` is a ground context stage. Every entity kind transitions into it (`host.into.default`, `user.into.default`, `home.into.default`). It provides a place to put behavior that applies unconditionally to all entities.

Under the new model, `default` is a relationship target. Rather than requiring every entity kind to declare a boilerplate relationship, `default` should be structural — the relationship system automatically creates a `*-to-default` transition for every entity kind that participates in the pipeline. This avoids the need to add `den.relationships.cluster-to-default` whenever a new entity kind is introduced.

```nix
# Built-in: every entity kind automatically gets a relationship to default.
# Equivalent to:
#   den.relationships.${kind}-to-default = { from = kind; to = "default"; resolve = lib.singleton; };
# for every registered entity kind. No explicit declaration needed.
```

`default` behavior lives in `den.aspects.default` (or `den.default` as it is currently aliased).

### Flake Output Stages

`flake`, `flake-system`, `flake-os`, `flake-packages` etc. are not entities in the real-world sense. They are context shapes — attrsets representing arguments (`{system}`, `{host}`) that drive output generation.

Under the new model, these become relationships in the output pipeline:
```nix
den.relationships.flake-to-systems = {
  from = "flake";
  to = "flake-system";
  resolve = _: map (system: { inherit system; }) den.systems;
};
den.relationships.flake-system-to-os = {
  from = "flake-system";
  to = "flake-os";
  resolve = { system }: map (host: { inherit host; }) (builtins.attrValues den.hosts.${system});
};
```

Their behavior (the output adapters that produce `nixosConfigurations`, `homeConfigurations`, etc.) moves to `den.aspects` with relationship-scoped activation.

### The makeHomeEnv Chain (host → hm-host → hm-user)

The `makeHomeEnv` factory currently generates a 3-node ctx chain for each home environment (home-manager, hjem, maid):

```
host.into.hm-host → hm-host.into.hm-user → hm-user.provides.hm-user
```

Under the new model, this becomes relationship declarations + aspects:

```nix
# Relationships (what makeHomeEnv generates):
den.relationships.host-to-hm-host = {
  from = "host";
  to = "hm-host";
  resolve = detectHost { className = "homeManager"; ... };
  aspect = "hm-host";  # activates den.aspects.hm-host
};
den.relationships.hm-host-to-hm-user = {
  from = "hm-host";
  to = "hm-user";
  resolve = intoClassUsers "homeManager";
  aspect = "hm-user";  # activates den.aspects.hm-user
};

# Behavior (the aspects that activate at each stage):
den.aspects.hm-host = { host }: {
  ${host.class}.imports = [ host.homeManager.module ];
};
den.aspects.hm-user = forwardToHost { ... };
```

The `makeHomeEnv` factory continues to exist but generates relationship + aspect pairs instead of ctx nodes. Its interface stays the same — callers pass `{ className, optionPath, getModule, forwardPathFn }` and get declarations back.

### Scope Binding (What ctxApply Becomes)

`ctxApply` currently stamps `__ctx` and `__scopeHandlers` on an aspect so parametric functions receive entity values as args. This mechanism survives but is no longer tied to `den.ctx`.

When the relationship pipeline transitions from one stage to another, it creates scope handlers from the context dict (`{host}`, `{host, user}`, etc.) and stamps them on the target aspect. This is a pipeline concern, not a class/entity concern. The function moves from `ctx-apply.nix` into the relationship handler.

## File Reorganization

### Current Layout (scattered)

```
nix/lib/types.nix                        # hostType + userType + homeType (290 lines, all mixed)
nix/lib/ctx-types.nix                    # ctxTreeType, ctxSubmodule, intoCtxType
nix/lib/ctx-apply.nix                    # ctxApply functor
nix/nixModule/ctx.nix                    # den.ctx option declaration
modules/context/host.nix                 # den.ctx.host (into, provides)
modules/context/user.nix                 # den.ctx.user (into, provides)
modules/context/has-aspect.nix           # hasAspect query API
modules/context/perHost-perUser.nix      # deprecated guards
modules/options.nix                      # schemaEntryType, den.hosts/homes/schema
modules/aspects/provides/home-manager.nix # den.ctx.home buried here
```

### Proposed Layout

**Entity schemas (entity-per-file):**
```
nix/lib/entities/
  _types.nix          # Shared: strOpt, systemType, homeSystemType, schemaEntryType
  _has-aspect.nix     # hasAspect entity query module (from modules/context/has-aspect.nix)
  host.nix            # hostSubmodule (entity shape options)
  user.nix            # userSubmodule (entity shape options)
  home.nix            # homeSubmodule (entity shape options, extracted from types.nix)
  home-env.nix        # makeHomeEnv factory
```

**Relationships (new):**
```
nix/lib/relationships/
  types.nix           # relationshipType (nested-capable for namespace reuse)
  handler.nix         # relationship handler for fx pipeline (replaces transitionHandler)

modules/relationships/
  host.nix            # host-to-users, host-to-default, host-to-hm-host, etc.
  user.nix            # user-to-default
  home.nix            # home-to-default
  flake.nix           # flake output pipeline relationships
```

**Deletions:**
- `den.ctx` option — fully removed
- `nix/lib/ctx-types.nix` — `ctxSubmodule` and `intoCtxType` no longer needed
- `nix/lib/ctx-apply.nix` — scope binding moves into relationship handler
- `nix/nixModule/ctx.nix` — replaced by `den.relationships` option
- `modules/context/host.nix` — `into`/`provides` move to `modules/relationships/host.nix`
- `modules/context/user.nix` — same
- `modules/context/perHost-perUser.nix` — deprecated, removed
- `nix/lib/types.nix` — split into per-entity files

### Migration Path

**Phase 1 (this branch):** Consolidate entity types into `nix/lib/entities/` (rename + split, no behavioral changes). Keep `den.ctx` working as-is during this phase. The `nix/lib/types.nix` split must provide re-exports from the original path so existing imports (`modules/options.nix`, `modules/aspects/definition.nix`, and any flake-level consumers) continue to work. Verify by grepping for all `types.nix` imports before splitting.

**Phase 2 (relationship policies):** Introduce `den.relationships`. Extract `into.*` from ctx nodes into relationship declarations. Behavior on ctx nodes moves to `den.aspects`.

**Phase 3 (ctx removal):** Remove `den.ctx` entirely. Update all consumers (templates, batteries, tests).

**Downstream migration surface:** Templates and batteries referencing intermediate ctx nodes (`den.ctx.hm-host`, `den.ctx.flake-packages`, etc.) need updating in Phase 3. This includes `templates/ci/modules/features/` test fixtures and `templates/flake-parts-modules/` which builds custom `into` chains. Battery modules contributing `includes` to ctx nodes (`den.ctx.user.includes`, `den.ctx.default.includes`) move to contributing to the equivalent `den.aspects` entries.

## Relationship to Other Specs

- **Relationship Policies** (`2026-04-20-relationship-policies-design.md`): Defines the `den.relationships` system in detail. This spec provides the motivation and the migration path for getting there. **Note:** The April 20 spec predates Vic's feedback and still references `den.ctx` in its "What stays" section and activation model (level 3: `den.ctx.<kind>.relationships`). It needs revision to align with the full ctx removal decision — specifically, the inline sugar section and activation model level 3 need new homes outside `den.ctx`.
- **Capabilities Design**: Aspects contain capability keys (Nix config classes). Structural detection determines which classes an aspect emits. Orthogonal to this spec — capabilities are about behavior, not data or relationships.
- **provide-to Effects**: Cross-entity routing currently in `provides` moves to relationship policies, which emit `provide-to` effects.

## Prior Art and Design Rationale

The three-way separation (entity structure, entity relationships, resolution behavior) is a universal pattern in mature systems. See companion document `2026-04-21-ctx-as-classes-prior-art.md` for detailed analysis.

### Key insight

Every system that ages well separates three concerns:
1. **What an entity IS** (structure/schema) — `den.schema.*` + entity type definitions
2. **How entities RELATE** (transitions) — `den.relationships`
3. **How entities RESOLVE** (behavior) — `den.aspects` + fx pipeline handlers

Systems that merge any two develop god-object problems. `den.ctx` merged relationships and behavior — this design separates them.

## Resolved Questions (from Vic's feedback)

1. **`default` is not an entity type.** It is a ground stage that all entity kinds transition into. Under the new model it is a relationship target with associated behavior in `den.aspects.default`.

2. **Flake output stages are not entities.** They are context shapes (argument attrsets) for output generation. They become relationships in the output pipeline.

3. **Namespaces share relationships.** Just as aspects (behavior) are shared via namespaces, relationships should be shareable too. `den.relationships` must support nesting for the denful project's reusable batteries.

4. **`ctxTreeType` nesting is needed** — for organizational purposes in large namespace trees (denful). Relationships inherit this nested structure.

5. **Battery `includes` on intermediate nodes** (e.g., `den.ctx.hm-host.includes`): These are behavior scoped to a relationship stage. After migration, the behavior moves to `den.aspects.hm-host` (or equivalent) which activates when the corresponding relationship resolves.

6. **`den.ctx` is fully removed.** It is not renamed, not kept for backwards compat. The `into` part becomes `den.relationships`. The behavior part becomes regular `den.aspects`. The name "ctx" leaks implementation details of the old context-passing mechanism.

## Open Questions

1. **Scoped behavior activation mechanism**: How exactly does behavior know it should activate when a relationship resolves? Option A (behavior on relationship), Option B (conditional aspects with predicates), or Option C (intermediate aspects activated by pipeline) — needs prototyping to determine the right ergonomics.

2. **Schema entry auto-resolution**: Currently `options.nix` checks `den.ctx ? ${kind}` to gate entity participation. With `den.ctx` removed, what gates this? Likely answer: check whether any relationship has `from = kind` or `to = kind` — if an entity kind participates in any relationship, it participates in resolution. Alternatively, `den.schema ? ${kind}` may suffice since schema existence already implies the entity kind is registered. Needs confirmation during Phase 2.

3. **Provides self-identity**: Currently `den.ctx.host.provides.host = {host}: host.aspect`. This is universal — every entity's aspect IS its identity. With ctx removed, does the pipeline infer this automatically, or does each relationship declare it?
