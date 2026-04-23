# Phase 2b: Introduce den.relationships

> **For agentic workers:** REQUIRED: Use superpowers-extended-cc:subagent-driven-development (if subagents available) or superpowers-extended-cc:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Introduce `den.relationships` as first-class relationship declarations that synthesize into the existing `into-transition` pipeline machinery — zero handler changes needed.

**Architecture:** Relationships are pure data (`{ from, to, resolve }`). At pipeline entry, they are compiled into `into`-style functions and merged into the root aspect's `meta.into`. The existing `emitTransitions` and `transitionHandler` process them unchanged. This is additive — `den.ctx.*.into` continues working alongside `den.relationships`.

**Tech Stack:** Nix, nix-unit, flake-parts

**Spec:** `docs/superpowers/specs/2026-04-20-relationship-policies-design.md` (Layer 1 only — policies)

**Branch:** `feat/rm-legacy`

**Test command:** `nix develop -c just ci`

**Format command:** `nix develop -c just fmt`

**Important repo conventions:**
- Stage new files before nix eval: `git add <file>`
- Format before committing: `nix develop -c just fmt`
- Commit with: `git -c core.hooksPath=/dev/null commit -m "..."`
- No Co-Authored-By trailer
- Use `--override-input den .` for template tests

**Scope boundary:** This plan covers Layer 1 (relationship policy declarations + pipeline injection) ONLY. Layer 2 (per-relationship named effects) and Layer 3 (cross-entity provide-to) are separate future work. The existing `into-transition` effect is reused, not replaced.

---

### Task 0: Define relationship type and den.relationships option

**Goal:** Create the `relationshipType` and declare the `den.relationships` option.

**Files:**
- Create: `nix/lib/relationship-types.nix`
- Create: `nix/nixModule/relationships.nix`
- Modify: `nix/lib/default.nix` (add relationshipTypes to den-lib)
- Modify: `nix/nixModule/default.nix` (add relationships.nix to import list)

**Acceptance Criteria:**
- [ ] `relationshipType` is a submodule with `from` (string), `to` (string), `resolve` (function)
- [ ] `den.relationships` option is declared with type `lazyAttrsOf relationshipType`
- [ ] `nix develop -c just ci` passes (additive, no regressions)

**Verify:** `nix develop -c just ci`

**Steps:**

- [ ] **Step 1: Create `nix/lib/relationship-types.nix`**

A relationship is pure data: `from` (entity kind name), `to` (target kind/stage name), `resolve` (function that takes context and returns list of target contexts).

```nix
# nix/lib/relationship-types.nix
#
# Relationship type definitions. A relationship declares how one entity
# kind transitions to another — pure topology, no behavior.
{ lib, ... }:
let
  relationshipType = lib.types.submodule {
    options = {
      from = lib.mkOption {
        type = lib.types.str;
        description = "Source entity kind (e.g., 'host')";
      };
      to = lib.mkOption {
        type = lib.types.str;
        description = "Target entity kind or stage name (e.g., 'user', 'hm-host')";
      };
      resolve = lib.mkOption {
        type = lib.types.raw;
        description = ''
          Function that takes accumulated pipeline context and returns
          a list of target context attrsets.

          Example: { host }: map (user: { inherit host user; }) (lib.attrValues host.users)
        '';
      };
    };
  };
in
{
  inherit relationshipType;
}
```

- [ ] **Step 2: Create `nix/nixModule/relationships.nix`**

```nix
# nix/nixModule/relationships.nix
{ den, lib, ... }:
let
  inherit (den.lib.relationshipTypes) relationshipType;
in
{
  options.den.relationships = lib.mkOption {
    description = "Relationship policies — declare how entity kinds relate.";
    default = { };
    defaultText = lib.literalExpression "{ }";
    type = lib.types.lazyAttrsOf relationshipType;
  };
}
```

- [ ] **Step 3: Register in den-lib and nixModule**

In `nix/lib/default.nix`, add to den-lib mapAttrs:
```nix
relationshipTypes = ./relationship-types.nix;
```

In `nix/nixModule/default.nix`, add to imports list (between `./stages.nix` and `./aspects.nix`):
```nix
./relationships.nix
```

- [ ] **Step 4: Stage, format, test, commit**

```bash
git add nix/lib/relationship-types.nix nix/nixModule/relationships.nix
nix develop -c just fmt
nix develop -c just ci
git add nix/lib/relationship-types.nix nix/nixModule/relationships.nix nix/lib/default.nix nix/nixModule/default.nix
git -c core.hooksPath=/dev/null commit -m "feat: add den.relationships option type for relationship policies"
```

---

### Task 1: Synthesize relationships into pipeline entry

**Goal:** At pipeline entry (`mkPipeline`), compile `den.relationships` into `into`-style functions and merge them into the root aspect's `meta.into`.

**Files:**
- Modify: `nix/lib/aspects/fx/pipeline.nix` (~10 lines added to `mkPipeline`)

**Acceptance Criteria:**
- [ ] Relationships with matching `from` kind are compiled into `into` functions
- [ ] The synthesized `into` is merged with the root aspect's existing `meta.into`
- [ ] The existing `into-transition` handler processes them unchanged
- [ ] Existing tests pass — no regressions (445/467 baseline)

**Verify:** `nix develop -c just ci`

**Steps:**

- [ ] **Step 1: Understand the injection point**

In `pipeline.nix`, `mkPipeline` receives `{ self, ctx }` and passes `self` to `aspectToEffect`. The `self` aspect may already have `meta.into` (from ctxApply). We need to merge relationship-synthesized `into` functions alongside it.

The tricky part: relationships are keyed by `from` kind, but the pipeline doesn't know what "kind" the root aspect is. However, the root aspect's `__ctx` tells us — it contains the entity values (e.g., `{ host = config; }`). The keys of `__ctx` ARE the current context kinds.

Actually simpler: each relationship has a `resolve` function that takes context. We group relationships by `to` (the target), and synthesize an `into` function: `ctx → { ${rel.to} = rel.resolve ctx; }`. Multiple relationships targeting the same `to` concatenate their results (lists).

- [ ] **Step 2: Add relationship synthesis to mkPipeline**

In `pipeline.nix`, before the `comp = aspectToEffect self;` line, synthesize relationship into functions and merge into self:

```nix
mkPipeline =
  {
    extraHandlers ? { },
    extraState ? { },
    class,
  }:
  {
    self,
    ctx,
  }:
  let
    # Synthesize den.relationships into an into-style function.
    # Groups by target (rel.to), concatenates resolve results per target.
    relationships = den.relationships or { };
    relationshipInto =
      if relationships == { } then null
      else
        rCtx:
        builtins.foldl' (
          acc: rel:
          let
            targets = rel.resolve rCtx;
          in
          acc // {
            ${rel.to} = (acc.${rel.to} or [ ]) ++ (if builtins.isList targets then targets else [ targets ]);
          }
        ) { } (builtins.attrValues relationships);

    # Merge relationship into with aspect's existing into (from ctx.into or meta.into).
    existingInto = self.meta.into or self.into or null;
    mergedInto =
      if relationshipInto != null && existingInto != null then
        ctx':
        let
          a = existingInto ctx';
          b = relationshipInto ctx';
        in
        # Deep merge: concatenate lists at leaves (same as intoCtxType merge)
        a // builtins.mapAttrs (k: vb:
          if a ? ${k} then
            let va = a.${k}; in
            if builtins.isList va && builtins.isList vb then va ++ vb
            else vb
          else vb
        ) b
      else if relationshipInto != null then relationshipInto
      else existingInto;

    # Inject merged into onto self
    effectiveSelf =
      if mergedInto != null then
        self // { meta = (self.meta or {}) // { into = mergedInto; }; }
      else
        self;

    comp = aspectToEffect effectiveSelf;
    # ... rest unchanged
```

Replace the existing `comp = aspectToEffect self;` with `comp = aspectToEffect effectiveSelf;`. The rest of mkPipeline stays unchanged.

- [ ] **Step 3: Format, test, commit**

```bash
nix develop -c just fmt
nix develop -c just ci
git add nix/lib/aspects/fx/pipeline.nix
git -c core.hooksPath=/dev/null commit -m "feat: synthesize den.relationships into pipeline entry"
```

---

### Task 2: Add relationship test fixture

**Goal:** Create a test that declares a relationship via `den.relationships` and verifies it produces the same pipeline result as the equivalent `den.ctx.*.into`.

**Files:**
- Create: `templates/ci/modules/features/relationships.nix`

**Acceptance Criteria:**
- [ ] Test declares `den.relationships.test-host-to-custom` with `from = "host"`, `to = "custom-stage"`, and a resolve function
- [ ] Test verifies the relationship produces behavior at the custom stage (via `den.stages.custom-stage`)
- [ ] Test verifies relationships coexist with existing `den.ctx.*.into` transitions

**Verify:** `nix develop -c nix-unit --override-input den . --flake ./templates/ci#.tests.relationships`

**Steps:**

- [ ] **Step 1: Study existing test patterns**

Read existing test fixtures to understand the pattern:
- `templates/ci/modules/features/stages.nix` — the stage tests we just added
- `templates/ci/modules/features/custom-ctx.nix` — tests custom ctx nodes
- `templates/ci/modules/features/ctx-chain.nix` — tests ctx transition chains

Tests define aspects/hosts/users, set config, then assert on resolved values.

- [ ] **Step 2: Create test fixture**

Create `templates/ci/modules/features/relationships.nix` with:

a. A `den.relationships.host-to-test-stage` relationship:
   - `from = "host"`, `to = "test-rel-stage"`
   - `resolve = { host }: [ { inherit host; } ]` (simple passthrough)

b. A `den.stages.test-rel-stage` with test nixos config (use `includes = [];` to trigger leaf detection)

c. Assertions that:
   - The relationship fires and the stage behavior appears in resolved config
   - Existing ctx transitions still work alongside

- [ ] **Step 3: Stage, format, test, commit**

```bash
git add templates/ci/modules/features/relationships.nix
nix develop -c just fmt
nix develop -c nix-unit --override-input den . --flake ./templates/ci#.tests.relationships
nix develop -c just ci
git add templates/ci/modules/features/relationships.nix
git -c core.hooksPath=/dev/null commit -m "test: add relationships integration test"
```

---

### Task 3: Add den.schema.*.relationships activation

**Goal:** Enable entity-kind-scoped relationship activation via `den.schema.<kind>.relationships`.

**Files:**
- Modify: `modules/options.nix` (add `relationships` option to schema entry type)
- Modify: `nix/lib/aspects/fx/pipeline.nix` (filter relationships by `from` matching schema kind)

**Acceptance Criteria:**
- [ ] `den.schema.host.relationships = [ den.relationships.my-policy ]` activates a policy for all hosts
- [ ] Only relationships whose `from` matches the current entity kind are activated
- [ ] Global `den.relationships` are always active (no `from` filtering at that level)

**Verify:** `nix develop -c just ci`

**Steps:**

- [ ] **Step 1: Understand how schema kind reaches the pipeline**

The pipeline receives `class` and `ctx`. The `ctx` has entity keys (`host`, `user`). The "kind" is determined by which entity keys are present. For the schema activation, we need the pipeline to know which `den.schema.<kind>.relationships` to include.

Read `modules/options.nix` to understand how `schemaEntryType` works and how it injects `config.resolved`. The schema kind is `lib.last loc` (line 30 in options.nix).

- [ ] **Step 2: Add relationships option to schema entry**

In `modules/options.nix`, within `schemaEntryType`'s `resolvedCtx` module, add a `relationships` option:

```nix
options.relationships = lib.mkOption {
  description = "Relationship policies active for this entity kind.";
  type = lib.types.listOf lib.types.raw;
  default = [ ];
};
```

- [ ] **Step 3: Pass schema relationships to pipeline**

This is the trickiest part. The pipeline needs access to schema-scoped relationships. Options:
a. Merge schema relationships into `den.relationships` at module eval time
b. Pass them through `ctx` to the pipeline

Option (a) is cleaner — a config module that reads `den.schema.*.relationships` and registers them in `den.relationships`.

Explore both approaches and pick the simpler one. If this is too complex for this phase, defer and document.

- [ ] **Step 4: Format, test, commit**

```bash
nix develop -c just fmt
nix develop -c just ci
git -c core.hooksPath=/dev/null commit -m "feat: support den.schema.<kind>.relationships activation"
```

**Note:** This task may be deferred if the integration is too complex for this phase. The core relationship mechanism (Tasks 0-2) works without schema-scoped activation — global `den.relationships` is sufficient for now.

---

### Task 4: Verify and push

**Goal:** Run full test suite, format check, push.

**Acceptance Criteria:**
- [ ] `nix develop -c just fmt` produces no changes
- [ ] `nix develop -c just ci` passes (same pass count or better)
- [ ] Branch pushed to `sini/feat/rm-legacy`

**Verify:** `nix develop -c just ci`

**Steps:**

- [ ] **Step 1: Full verification**

```bash
nix develop -c just fmt
nix develop -c just ci
```

- [ ] **Step 2: Push**

```bash
git push sini feat/rm-legacy
```
