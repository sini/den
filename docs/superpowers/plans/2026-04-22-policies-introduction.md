# Phase 2b: Introduce den.policies

> **For agentic workers:** REQUIRED: Use superpowers-extended-cc:subagent-driven-development (if subagents available) or superpowers-extended-cc:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Introduce `den.policies` as first-class policy declarations that synthesize into the existing `into-transition` pipeline machinery — zero handler changes needed.

**Architecture:** Policies are pure data (`{ from, to, resolve }`). At pipeline entry, they are compiled into `into`-style functions and merged into the root aspect's `meta.into`. The existing `emitTransitions` and `transitionHandler` process them unchanged. This is additive — `den.ctx.*.into` continues working alongside `den.policies`.

**Tech Stack:** Nix, nix-unit, flake-parts

**Spec:** `docs/superpowers/specs/2026-04-20-policy-design.md` (Layer 1 only — policies)

**Branch:** `feat/rm-legacy`

**Test command:** `nix develop -c just ci`

**Format command:** `nix develop -c just fmt`

**Important repo conventions:**
- Stage new files before nix eval: `git add <file>`
- Format before committing: `nix develop -c just fmt`
- Commit with: `git -c core.hooksPath=/dev/null commit -m "..."`
- No Co-Authored-By trailer
- Use `--override-input den .` for template tests

**Scope boundary:** This plan covers Layer 1 (policy declarations + pipeline injection) ONLY. Layer 2 (per-policy named effects) and Layer 3 (cross-entity provide-to) are separate future work. The existing `into-transition` effect is reused, not replaced.

---

### Task 0: Define policy type and den.policies option

**Goal:** Create the `policyType` and declare the `den.policies` option.

**Files:**
- Create: `nix/lib/policy-types.nix`
- Create: `nix/nixModule/policies.nix`
- Modify: `nix/lib/default.nix` (add policyTypes to den-lib)
- Modify: `nix/nixModule/default.nix` (add policies.nix to import list)

**Acceptance Criteria:**
- [ ] `policyType` is a submodule with `from` (string), `to` (string), `resolve` (function)
- [ ] `den.policies` option is declared with type `lazyAttrsOf policyType`
- [ ] `nix develop -c just ci` passes (additive, no regressions)

**Verify:** `nix develop -c just ci`

**Steps:**

- [ ] **Step 1: Create `nix/lib/policy-types.nix`**

A policy is pure data: `from` (entity kind name), `to` (target kind/stage name), `resolve` (function that takes context and returns list of target contexts).

```nix
# nix/lib/policy-types.nix
#
# Policy type definitions. A policy declares how one entity
# kind transitions to another — pure topology, no behavior.
{ lib, ... }:
let
  policyType = lib.types.submodule {
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
  inherit policyType;
}
```

- [ ] **Step 2: Create `nix/nixModule/policies.nix`**

```nix
# nix/nixModule/policies.nix
{ den, lib, ... }:
let
  inherit (den.lib.policyTypes) policyType;
in
{
  options.den.policies = lib.mkOption {
    description = "Policies — declare how entity kinds relate.";
    default = { };
    defaultText = lib.literalExpression "{ }";
    type = lib.types.lazyAttrsOf policyType;
  };
}
```

- [ ] **Step 3: Register in den-lib and nixModule**

In `nix/lib/default.nix`, add to den-lib mapAttrs:
```nix
policyTypes = ./policy-types.nix;
```

In `nix/nixModule/default.nix`, add to imports list (between `./stages.nix` and `./aspects.nix`):
```nix
./policies.nix
```

- [ ] **Step 4: Stage, format, test, commit**

```bash
git add nix/lib/policy-types.nix nix/nixModule/policies.nix
nix develop -c just fmt
nix develop -c just ci
git add nix/lib/policy-types.nix nix/nixModule/policies.nix nix/lib/default.nix nix/nixModule/default.nix
git -c core.hooksPath=/dev/null commit -m "feat: add den.policies option type for policies"
```

---

### Task 1: Synthesize policies into pipeline entry

**Goal:** At pipeline entry (`mkPipeline`), compile `den.policies` into `into`-style functions and merge them into the root aspect's `meta.into`.

**Files:**
- Modify: `nix/lib/aspects/fx/pipeline.nix` (~10 lines added to `mkPipeline`)

**Acceptance Criteria:**
- [ ] Policies with matching `from` kind are compiled into `into` functions
- [ ] The synthesized `into` is merged with the root aspect's existing `meta.into`
- [ ] The existing `into-transition` handler processes them unchanged
- [ ] Existing tests pass — no regressions (445/467 baseline)

**Verify:** `nix develop -c just ci`

**Steps:**

- [ ] **Step 1: Understand the injection point**

In `pipeline.nix`, `mkPipeline` receives `{ self, ctx }` and passes `self` to `aspectToEffect`. The `self` aspect may already have `meta.into` (from ctxApply). We need to merge policy-synthesized `into` functions alongside it.

The tricky part: policies are keyed by `from` kind, but the pipeline doesn't know what "kind" the root aspect is. However, the root aspect's `__ctx` tells us — it contains the entity values (e.g., `{ host = config; }`). The keys of `__ctx` ARE the current context kinds.

Actually simpler: each policy has a `resolve` function that takes context. We group policies by `to` (the target), and synthesize an `into` function: `ctx → { ${rel.to} = rel.resolve ctx; }`. Multiple policies targeting the same `to` concatenate their results (lists).

- [ ] **Step 2: Add policy synthesis to mkPipeline**

In `pipeline.nix`, before the `comp = aspectToEffect self;` line, synthesize policy into functions and merge into self:

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
    # Synthesize den.policies into an into-style function.
    # Groups by target (rel.to), concatenates resolve results per target.
    policies = den.policies or { };
    policyInto =
      if policies == { } then null
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
        ) { } (builtins.attrValues policies);

    # Merge policy into with aspect's existing into (from ctx.into or meta.into).
    existingInto = self.meta.into or self.into or null;
    mergedInto =
      if policyInto != null && existingInto != null then
        ctx':
        let
          a = existingInto ctx';
          b = policyInto ctx';
        in
        # Deep merge: concatenate lists at leaves (same as intoCtxType merge)
        a // builtins.mapAttrs (k: vb:
          if a ? ${k} then
            let va = a.${k}; in
            if builtins.isList va && builtins.isList vb then va ++ vb
            else vb
          else vb
        ) b
      else if policyInto != null then policyInto
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
git -c core.hooksPath=/dev/null commit -m "feat: synthesize den.policies into pipeline entry"
```

---

### Task 2: Add policy test fixture

**Goal:** Create a test that declares a policy via `den.policies` and verifies it produces the same pipeline result as the equivalent `den.ctx.*.into`.

**Files:**
- Create: `templates/ci/modules/features/policies.nix`

**Acceptance Criteria:**
- [ ] Test declares `den.policies.test-host-to-custom` with `from = "host"`, `to = "custom-stage"`, and a resolve function
- [ ] Test verifies the policy produces behavior at the custom stage (via `den.stages.custom-stage`)
- [ ] Test verifies policies coexist with existing `den.ctx.*.into` transitions

**Verify:** `nix develop -c nix-unit --override-input den . --flake ./templates/ci#.tests.policies`

**Steps:**

- [ ] **Step 1: Study existing test patterns**

Read existing test fixtures to understand the pattern:
- `templates/ci/modules/features/stages.nix` — the stage tests we just added
- `templates/ci/modules/features/custom-ctx.nix` — tests custom ctx nodes
- `templates/ci/modules/features/ctx-chain.nix` — tests ctx transition chains

Tests define aspects/hosts/users, set config, then assert on resolved values.

- [ ] **Step 2: Create test fixture**

Create `templates/ci/modules/features/policies.nix` with:

a. A `den.policies.host-to-test-stage` policy:
   - `from = "host"`, `to = "test-rel-stage"`
   - `resolve = { host }: [ { inherit host; } ]` (simple passthrough)

b. A `den.stages.test-rel-stage` with test nixos config (use `includes = [];` to trigger leaf detection)

c. Assertions that:
   - The policy fires and the stage behavior appears in resolved config
   - Existing ctx transitions still work alongside

- [ ] **Step 3: Stage, format, test, commit**

```bash
git add templates/ci/modules/features/policies.nix
nix develop -c just fmt
nix develop -c nix-unit --override-input den . --flake ./templates/ci#.tests.policies
nix develop -c just ci
git add templates/ci/modules/features/policies.nix
git -c core.hooksPath=/dev/null commit -m "test: add policies integration test"
```

---

### Task 3: Add den.schema.*.policies activation

**Goal:** Enable entity-kind-scoped policy activation via `den.schema.<kind>.policies`.

**Files:**
- Modify: `modules/options.nix` (add `policies` option to schema entry type)
- Modify: `nix/lib/aspects/fx/pipeline.nix` (filter policies by `from` matching schema kind)

**Acceptance Criteria:**
- [ ] `den.schema.host.policies = [ den.policies.my-policy ]` activates a policy for all hosts
- [ ] Only policies whose `from` matches the current entity kind are activated
- [ ] Global `den.policies` are always active (no `from` filtering at that level)

**Verify:** `nix develop -c just ci`

**Steps:**

- [ ] **Step 1: Understand how schema kind reaches the pipeline**

The pipeline receives `class` and `ctx`. The `ctx` has entity keys (`host`, `user`). The "kind" is determined by which entity keys are present. For the schema activation, we need the pipeline to know which `den.schema.<kind>.policies` to include.

Read `modules/options.nix` to understand how `schemaEntryType` works and how it injects `config.resolved`. The schema kind is `lib.last loc` (line 30 in options.nix).

- [ ] **Step 2: Add policies option to schema entry**

In `modules/options.nix`, within `schemaEntryType`'s `resolvedCtx` module, add a `policies` option:

```nix
options.policies = lib.mkOption {
  description = "Policies active for this entity kind.";
  type = lib.types.listOf lib.types.raw;
  default = [ ];
};
```

- [ ] **Step 3: Pass schema policies to pipeline**

This is the trickiest part. The pipeline needs access to schema-scoped policies. Options:
a. Merge schema policies into `den.policies` at module eval time
b. Pass them through `ctx` to the pipeline

Option (a) is cleaner — a config module that reads `den.schema.*.policies` and registers them in `den.policies`.

Explore both approaches and pick the simpler one. If this is too complex for this phase, defer and document.

- [ ] **Step 4: Format, test, commit**

```bash
nix develop -c just fmt
nix develop -c just ci
git -c core.hooksPath=/dev/null commit -m "feat: support den.schema.<kind>.policies activation"
```

**Note:** This task may be deferred if the integration is too complex for this phase. The core policy mechanism (Tasks 0-2) works without schema-scoped activation — global `den.policies` is sufficient for now.

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
