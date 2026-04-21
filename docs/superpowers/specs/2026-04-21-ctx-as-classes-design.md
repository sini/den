# den.ctx as Class Registry

**Date:** 2026-04-21
**Branch:** feat/rm-legacy
**Status:** Draft — pending peer review

## Problem

`den.ctx` is overloaded. A single `den.ctx.host` node simultaneously serves as:

1. **Class definition** — what "host" means structurally (transitions, providers, schema shape)
2. **Schema registry** — `den.ctx ? ${kind}` gates whether an entity kind participates in aspect resolution
3. **Scope binder** — `ctxApply` stamps `__scopeHandlers` so parametric functions receive `{ host }` args
4. **Aspect factory** — calling `den.ctx.host { host = config; }` produces an aspect-shaped attrset for the pipeline

This conflation causes:
- **~24 ctx nodes** where only 3-4 represent real entity types; the rest are intermediate pipeline scaffolding (`hm-host`, `hm-user`, `flake-system`, `flake-os`, etc.)
- **`into` on every node** — transition topology baked into class definitions, making classes responsible for knowing their relationships
- **`provides` doing double duty** — self-identity (`provides.host = {host}: host.aspect`) and cross-class routing (`provides.hm-user = forwardToHost {...}`) in the same mechanism
- **No place to define an entity's shape** (options like `name`, `system`, `class`, `users`) alongside its pipeline behavior — these live in separate files (`nix/lib/types.nix` vs `modules/context/*.nix`)

Vic's position: remove `den.ctx` entirely.
Sini's position: the class-definition role is real and needed; keep the name for backwards compatibility but treat nodes as classes.

## Design: ctx = Class Registry

### Core Principle

`den.ctx.host` is a **class definition**, not a context pipeline node. A class defines:
- What structural shape entities of this kind have (options)
- What capability keys it recognizes (nixos, darwin, homeManager, etc.)

Everything else — transitions, forwarding, output routing — moves out of the class definition into purpose-built systems.

### What Stays in den.ctx

Each entry in `den.ctx` is a class. The registry shrinks from ~24 nodes to the real entity types:

| Class | Purpose |
|-------|---------|
| `host` | OS configuration entity (nixos/darwin/systemManager) |
| `user` | User account entity (nested under host) |
| `home` | Standalone home-manager configuration entity |
| `default` | Base aspect target (receives unconditional includes) |

A class definition contains:
- **Schema shape** — the entity's options (name, system, class, aspect, etc.), currently scattered in `nix/lib/types.nix`
- **Capability keys** — which class keys (nixos, darwin, homeManager) this entity type recognizes, detected structurally per the capabilities design
- **Metadata** — description, documentation

A class definition does NOT contain:
- `into` transitions (moves to relationship policies)
- `provides` declarations (self-identity becomes implicit; cross-class routing moves to relationships)
- `__functor` magic (ctxApply simplifies to scope binding only)

### What Moves to Relationship Policies

Every current `into` definition follows one pattern: enumerate entities, build context dict. These are relationship declarations, not class behavior.

**Before (on class):**
```nix
den.ctx.host.into.user = { host }:
  map (user: { inherit host user; }) (lib.attrValues host.users);
```

**After (relationship policy):**
```nix
den.relationships.host-users = {
  from = "host";
  to = "user";
  resolve = { host }:
    map (user: { inherit host user; }) (lib.attrValues host.users);
};
```

The class doesn't know about its transitions. Relationships are declared externally and the pipeline walks them.

### What Becomes Implicit

**Self-identity provides** — Every class currently declares `provides.X = {x}: x.aspect`. This is universal and mechanical. Under the class model, an entity's aspect IS its identity. No declaration needed; the pipeline infers it.

**`ctxApply` simplifies** — Today it preserves `into`, `provides`, stamps `__ctx` + `__scopeHandlers`. After: it just stamps scope handlers (binding entity values as parametric args). No `into` or `provides` to carry.

### What Gets Eliminated

**Intermediate ctx nodes** disappear entirely:

| Node | Current Role | Replacement |
|------|-------------|-------------|
| `hm-host`, `hm-user` | Home-manager pipeline scaffolding | Relationship policy with `homeEnv` activation |
| `maid-host`, `maid-user` | Maid pipeline scaffolding | Same |
| `hjem-host`, `hjem-user` | Hjem pipeline scaffolding | Same |
| `wsl-host` | WSL conditional pipeline | Relationship policy with conditional activation |
| `flake`, `flake-system` | Flake output enumeration | Output adapter system |
| `flake-os`, `flake-hm` | OS/HM output routing | Output adapter system |
| `flake-packages`, etc. | Per-output-type routing | Output adapter system |
| `os` | Import-tree OS forwarding | Capability on host class |
| `hm` (import-tree) | Import-tree HM forwarding | Capability on home/user class |

The `makeHomeEnv` 3-node chain (`host.into.X-host` -> `X-host.into.X-user` -> `X-user.provides`) collapses to a single relationship policy declaration.

### ctxSubmodule Simplification

**Before:**
```nix
ctxSubmodule = lib.types.submodule {
  imports = den.lib.aspects.types.aspectType.getSubModules;
  options.into = ...;        # transition functions
  options.__functor = ...;   # ctxApply callable
  # Plus all aspectType options (name, meta, includes, provides, freeform class keys)
};
```

**After:**
```nix
classType = lib.types.submodule {
  options = {
    # Entity shape — the options this class defines
    entityOptions = ...;
    # Class metadata
    description = ...;
    # Capability keys this class recognizes (bootstrapped from entity definitions)
    capabilities = ...;
  };
  # No into, no provides, no __functor
};
```

The class type is pure data. No callable functor, no transition functions.

### Schema Wiring

The schema auto-resolution in `options.nix` stays structurally similar but reads from the simplified class:

```nix
# Current: den.ctx.${kind} (filterAttrs ... // { ${kind} = config; })
# After:   den.lib.instantiateClass kind (filterAttrs ... // { ${kind} = config; })
```

The `den.ctx ? ${kind}` existence check still gates participation. The class registry remains the source of truth for "which entity kinds exist."

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

### Proposed Layout (entity-per-file)

```
nix/lib/entities/
  _types.nix          # Shared: strOpt, systemType, homeSystemType, schemaEntryType, classType definition
  _has-aspect.nix     # hasAspect entity query module (from modules/context/has-aspect.nix)
  host.nix            # hostType (entity shape) + den.ctx.host (class def)
  user.nix            # userType (entity shape) + den.ctx.user (class def)
  home.nix            # homeType (entity shape) + den.ctx.home (class def, extracted)
  home-env.nix        # makeHomeEnv factory (generates relationship policies for hm/hjem/maid)

nix/lib/ctx/
  types.nix           # ctxTreeType (simplified — no intoCtxType after into removal)
  apply.nix           # class instantiation (simplified ctxApply — scope binding only)
```

**Key principle:** Entity type and class definition live in the same file because they're two faces of the same concept. A host's shape (what options it has) and its class identity (what capability keys it recognizes) are inherently coupled.

### Migration Path

This reorganization is a **rename + consolidate**, not a rewrite. The entity type code moves from `nix/lib/types.nix` into per-entity files. The class definitions move from `modules/context/*.nix` into the same files. No behavioral changes in this step.

The behavioral changes (removing `into`/`provides` from classes, introducing relationship policies) happen in subsequent work as the relationship policies spec is implemented.

**Downstream migration surface:** Templates and batteries that reference intermediate ctx nodes (`den.ctx.hm-host`, `den.ctx.flake-packages`, etc.) will need updating when those nodes are eliminated. This includes `templates/ci/modules/features/` test fixtures and `templates/flake-parts-modules/` which builds custom `into` chains on `den.ctx.flake-parts`. Battery modules like `os-user.nix`, `mutual-provider.nix`, and `os-class.nix` that contribute `includes` to ctx nodes (`den.ctx.user.includes`, `den.ctx.default.includes`) are fine for surviving classes but the pattern of contributing to intermediate nodes (e.g., `den.ctx.hm-host.includes` in templates) needs a migration target. This downstream work is scoped to the relationship policies implementation, not this reorganization step.

**`ctxTreeType` structural detection hazard:** The recursive merge in `ctxTreeType` uses structural key sniffing (`into`, `provides`, `_`, `includes`, `_module`) to distinguish leaf ctx nodes from namespace containers. When `into`/`provides` are removed from class definitions, this heuristic changes. During migration, the detection keys must be updated to match whatever the simplified `classType` uses — or the tree type can be replaced with a flat registry if nested namespaces are no longer needed (see open question 4).

### Deletions

- `modules/context/perHost-perUser.nix` — deprecated guards, relationship policies replaces the pattern
- `modules/context/host.nix` — absorbed into `nix/lib/entities/host.nix`
- `modules/context/user.nix` — absorbed into `nix/lib/entities/user.nix`
- `nix/lib/types.nix` — split into per-entity files + `_types.nix`

## Relationship to Other Specs

- **Relationship Policies** (`2026-04-20-relationship-policies-design.md`): This spec defines where `into`/`provides` move TO. The class registry spec defines what they move FROM.
- **Capabilities Design**: Classes recognize capability keys via structural detection. The class registry is where capability bootstrapping happens (known class names from entity definitions).
- **provide-to Effects**: Cross-class routing currently in `provides` moves to relationship policies, which emit `provide-to` effects.

## Prior Art and Design Rationale

The three-way separation (entity structure, entity relationships, resolution behavior) is a universal pattern in mature systems. Den's class registry design draws from several:

### Haskell Typeclasses — closest analog

A Haskell `data` declaration defines structure. A `typeclass instance` declares capabilities separately. `instance Resolvable Host where resolve = ...` adds behavior without modifying the Host definition.

Den's mapping: `den.ctx.host` = type declaration (what a host IS). Capability keys (nixos, darwin) = typeclass instances (what a host CAN DO). Relationship policies = typeclass constraints (`Resolvable a => Deployable a` — pipeline ordering).

This validates separating class definitions from resolution behavior. The class is the type; capabilities and relationships are declared externally.

### Kubernetes CRDs + Controllers — spec/status split

CRDs define pure schema (what fields a resource has). Controllers provide reconciliation behavior (converge actual state toward desired state). They're separate processes — the API server stores data, controllers add behavior.

Den's mapping: entity type options = CRD spec (declared shape). Resolution pipeline = controller (converges aspects into NixOS config). `config.resolved` = status (observed output). This validates keeping the class definition as pure data with no behavioral __functor.

### Rails ActiveRecord — relationship vocabulary

`has_many :users`, `belongs_to :host` — declarative macros that read as prose. Relationships are metadata, not behavior. Rails also separates schema (migrations) from the model class.

Den's mapping: `den.relationships.host-users = { from = "host"; to = "user"; ... }` follows the same declarative pattern. The relationship spec is metadata that the pipeline walks.

**Anti-pattern to avoid:** Rails merges too much into model classes — god-object models with 500+ lines mixing query logic, validation, and callbacks. Den should resist the temptation to add behavior to class definitions.

### Terraform — implicit relationship detection

Terraform infers its dependency DAG from attribute references (`vpc_id = aws_vpc.main.id`). Explicit `depends_on` is the escape hatch. Most relationships are discovered, not declared.

Den could similarly infer relationships from how entities reference each other (a home-manager config references a user which references a host). Explicit relationship policies are the primary mechanism, but structural inference (per the capabilities design) complements them.

### ECS — composition over classification

In Entity-Component-System, an entity is nothing — just an ID. Meaning comes from which components are attached. Systems query by component signature.

This validates den's aspect model: an entity gains capabilities by which aspects are attached, not by its class hierarchy. The class registry defines the structural shape, but the actual configuration comes from aspect composition. Classes are constraints on valid compositions, not behavior prescriptions.

### Key insight

Every system that ages well separates three concerns:
1. **What an entity IS** (structure/schema) — den.ctx class definitions
2. **How entities RELATE** (associations) — den.relationships policies
3. **How entities RESOLVE** (behavior) — fx pipeline handlers

Systems that merge any two develop god-object problems. The ctx-as-classes design maintains this separation.

## Open Questions

1. **`default` class**: Is `default` a real class or just a catch-all aspect target? If aspects that aren't entity-bound still need a resolution target, `default` stays. If relationship policies handle unconditional includes differently, it might not need to be a class.

2. **Flake output adapters**: The flake ctx nodes (`flake`, `flake-system`, `flake-os`, etc.) are clearly not entity classes. What system replaces them? A separate output adapter registry? Or do they become relationship policies too (flake "relates to" its systems)?

3. **Namespace ctx**: `namespace-types.nix` defines per-namespace `ctx`. Does the class model apply to namespaces too, or are namespace ctx nodes a separate concept?

4. **`ctxTreeType` recursive merge**: Currently supports nested namespaces (`den.ctx.ns.inner`). If classes are flat (host, user, home, default), do we still need the recursive tree type?

5. **Battery `includes` on eliminated nodes**: Modules like `os-user.nix` and `mutual-provider.nix` contribute `den.ctx.user.includes` and `den.ctx.default.includes` — these survive since `user` and `default` are classes. But the pattern of contributing `includes` to intermediate nodes (e.g., `den.ctx.hm-host.includes` in templates) needs a new home. Do these become relationship policy configuration, or do they attach to the surviving parent class?

6. **`into` as inline sugar vs removal**: The relationship policies spec (2026-04-20) describes `into` on ctx nodes as syntactic sugar that desugars to policies. This spec says class definitions do NOT contain `into`. Clarify: does `into` survive as a convenience syntax on `den.ctx` that compiles to `den.relationships`, or is it fully removed? Recommendation: fully remove from class definitions; if sugar is wanted, provide it as a separate helper (`den.lib.relationship { from = "host"; into.user = ...; }`).
