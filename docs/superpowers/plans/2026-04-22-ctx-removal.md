# Phase 3c: Remove den.ctx

> **For agentic workers:** REQUIRED: Use superpowers-extended-cc:subagent-driven-development (if subagents available) or superpowers-extended-cc:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove `den.ctx` entirely — the final step in the four-way separation (Data/Relationships/Stages/Behavior). All `into` declarations are now handled by `den.relationships`, all scoped behavior by `den.stages`.

**Architecture:** The critical dependency chain is: ctxApply replacement FIRST (it's the pipeline entry point), THEN remove ctx into/provides (relationships + stages take over), THEN delete infrastructure. ctxApply is called by modules/outputs and modules/options to start the pipeline — without an alternative entry mechanism, removing anything from ctx nodes breaks OS config generation.

**Tech Stack:** Nix, nix-unit, flake-parts

**Branch:** `feat/rm-legacy`

**Test command:** `nix develop -c just ci`
**Format command:** `nix develop -c just fmt`

**Conventions:** Stage new files with `git add`, format before commit, commit with `git -c core.hooksPath=/dev/null commit`, no Co-Authored-By trailer, use timeout 600000ms for CI.

**Baseline:** 447/469 tests passing, 22 pre-existing failures.

**IMPORTANT ordering constraint:** ctxApply (`den.ctx.host { host = config; }`) is the pipeline entry point used by `modules/outputs/osConfigurations.nix`, `modules/outputs/hmConfigurations.nix`, `modules/outputs.nix`, `modules/options.nix`, and `nix/lib/home-env.nix`. These calls:
1. Take a ctx node and call it as a function (via `__functor`)
2. ctxApply stamps `__ctx`, `__scopeHandlers`, preserves `into` in `meta.into`, preserves `provides`
3. The result is passed to `den.lib.aspects.resolve` which feeds it into the pipeline

**You CANNOT remove `into` or `provides` from ctx nodes until ctxApply is replaced.** The pipeline entry depends on ctx nodes being complete aspect-shaped attrsets with into/provides/class-keys.

**IMPORTANT: Relationship resolve functions must guard context shape.** All resolve functions use `ctx:` (not destructured) and check `builtins.isAttrs ctx.host` before accessing fields. See `feedback_relationship_guards.md`.

**Key reference files:**
- `nix/lib/ctx-apply.nix` — ctxApply functor (to be replaced first)
- `nix/lib/aspects/fx/pipeline.nix` — pipeline synthesis (relationships → into)
- `nix/lib/aspects/fx/handlers/transition.nix` — transition handler (looks up ctx + stages)
- `modules/options.nix` — schema entry auto-resolution (uses ctx for gating)
- `modules/outputs/osConfigurations.nix` — calls `den.ctx.host { inherit host; }`
- `modules/outputs/hmConfigurations.nix` — calls `den.ctx.home { inherit home; }`
- `modules/outputs.nix` — calls `den.ctx.flake { }`
- `nix/lib/home-env.nix` — calls `den.ctx."${ctxName}-user" { ... }`

---

### Task 0: Create resolveStage — the ctxApply replacement

**Goal:** Create `den.lib.resolveStage` — a function that builds an aspect-shaped attrset from a stage node + context, replacing what ctxApply does today. This is the foundation for removing ctxApply.

**Files:**
- Create: `nix/lib/resolve-stage.nix`
- Modify: `nix/lib/default.nix` (add resolveStage to den-lib)

**Acceptance Criteria:**
- [ ] `resolveStage` takes a stage name and context attrset
- [ ] Returns an aspect-shaped attrset with `__ctx`, `__scopeHandlers`, stage behavior merged
- [ ] Does NOT use `__functor` — it's a plain function call
- [ ] `nix develop -c just ci` passes (additive, no consumers yet)

**Verify:** `nix develop -c just ci`

**Steps:**

- [ ] **Step 1: Read ctxApply to understand what it does**

Read `nix/lib/ctx-apply.nix`. ctxApply does:
1. `classAttrs = builtins.removeAttrs self structuralKeys` — preserves class keys (nixos, darwin, etc.)
2. `name = self.name or "<anon>"` — preserves name
3. `meta.into = self.into or (_: { })` — preserves into in meta (survives deferredModule)
4. `provides = self.provides or { }` — preserves provides
5. `includes = (self.includes or [ ]) ++ stageAsInclude` — merges stage includes
6. `__ctx = ctx` — carries context to pipeline
7. `__scopeHandlers = constantHandler ctx` — handler-closure for parametric arg resolution

`resolveStage` needs to do the same but reading from `den.stages.${name}` instead of a ctx node:
1. Look up `den.stages.${name} or {}`
2. Extract class keys, includes from the stage
3. Stamp `__ctx` and `__scopeHandlers` from the provided context
4. `meta.into` is NOT needed — pipeline synthesis handles relationships
5. `provides` comes from the stage (if any) — but stages shouldn't have provides. For the transition period, also look up `den.ctx.${name}.provides` as fallback.

- [ ] **Step 2: Implement resolveStage**

```nix
# nix/lib/resolve-stage.nix
#
# resolveStage — replacement for ctxApply.
# Builds an aspect-shaped attrset from a stage node + context.
# Does not use __functor — plain function call.
{ lib, den, ... }:
let
  inherit (den.lib.aspects.fx.handlers) constantHandler;

  structuralKeys = [
    "name" "description" "meta" "includes" "provides" "_module" "_"
  ];

  resolveStage = name: ctx:
    let
      stageNode = den.stages.${name} or {};
      # Fallback to ctx node for provides during transition
      ctxNode = (den.ctx or {}).${name} or {};
      classAttrs = builtins.removeAttrs stageNode structuralKeys;
      ctxClassAttrs = builtins.removeAttrs ctxNode (structuralKeys ++ ["into" "__functor"]);
      scopeHandlers = constantHandler ctx;
    in
    # Merge: ctx class keys as base, stage class keys override
    ctxClassAttrs // classAttrs // {
      name = stageNode.name or ctxNode.name or name;
      meta = {
        handleWith = null;
        excludes = [];
        provider = [];
      };
      provides = stageNode.provides or ctxNode.provides or {};
      includes = (ctxNode.includes or []) ++ (stageNode.includes or []);
      __ctx = ctx;
      __scopeHandlers = scopeHandlers;
    };
in
{
  inherit resolveStage;
}
```

- [ ] **Step 3: Register in den-lib**

Add to `nix/lib/default.nix`:
```nix
resolveStage = ./resolve-stage.nix;
```

Then `den.lib.resolveStage` is available as `den.lib.resolveStage.resolveStage name ctx`.

- [ ] **Step 4: Stage, format, test, commit**

```bash
git add nix/lib/resolve-stage.nix
nix develop -c just fmt
nix develop -c just ci
git add nix/lib/resolve-stage.nix nix/lib/default.nix
git -c core.hooksPath=/dev/null commit -m "feat: add den.lib.resolveStage — ctxApply replacement"
```

---

### Task 1: Replace ctxApply calls in production code

**Goal:** Replace all `den.ctx.X { args }` calls with `den.lib.resolveStage.resolveStage "X" args`.

**Files:**
- Modify: `modules/outputs/osConfigurations.nix` — replace `den.ctx.host { inherit host; }`
- Modify: `modules/outputs/hmConfigurations.nix` — replace `den.ctx.home { inherit home; }`
- Modify: `modules/outputs.nix` — replace `den.ctx.flake { }`
- Modify: `modules/options.nix` — replace `den.ctx.${kind}` gating and calls
- Modify: `nix/lib/home-env.nix` — replace `den.ctx."${ctxName}-user"` calls
- Modify: `templates/flake-parts-modules/modules/perSystem-forward.nix` — replace ctxApply call
- Modify: `templates/microvm/modules/microvm-integration.nix` — replace ctxApply calls

**Acceptance Criteria:**
- [ ] No `den.ctx.X { args }` calls remain in production code
- [ ] All calls use `den.lib.resolveStage.resolveStage` instead
- [ ] Entity participation gating in options.nix uses `den.stages ? ${kind}` or `den.relationships`
- [ ] `nix develop -c just ci` passes — 447+ tests

**Verify:** `nix develop -c just ci`

**Steps:**

- [ ] **Step 1: Read each file and replace ctxApply calls**

For each call site:
```nix
# Before:
den.ctx.host { inherit host; }
# After:
den.lib.resolveStage.resolveStage "host" { inherit host; }
```

For `modules/options.nix`, the gating check `den.ctx ? ${kind}` needs to change. Options:
- `den.stages ? ${kind}` — gate on stage existence
- Check if any relationship has `from = kind` — more correct but complex
- Keep `den.ctx ? ${kind}` temporarily — simplest, remove when ctx is deleted

Use the simplest option that passes tests.

- [ ] **Step 2: Handle home-env.nix dynamic calls**

`home-env.nix:65-66` calls `den.ctx."${ctxName}-user" { ... }`. Replace with:
```nix
den.lib.resolveStage.resolveStage "${ctxName}-user" { inherit host user; }
```

- [ ] **Step 3: Format, test, commit**

```bash
nix develop -c just fmt
nix develop -c just ci
git add modules/outputs/osConfigurations.nix modules/outputs/hmConfigurations.nix modules/outputs.nix modules/options.nix nix/lib/home-env.nix templates/flake-parts-modules/modules/perSystem-forward.nix templates/microvm/modules/microvm-integration.nix
git -c core.hooksPath=/dev/null commit -m "refactor: replace ctxApply calls with resolveStage"
```

---

### Task 2: Move ctx provides to stages

**Goal:** Move `provides` declarations from ctx nodes to stages. Now that ctxApply is no longer used, provides can live on stages — `resolveStage` reads them from there.

**Files:**
- Modify: `modules/context/host.nix` — move provides.host to `den.stages.host.provides.host`
- Modify: `modules/context/user.nix` — move provides.user to `den.stages.user.provides.user`
- Modify: `modules/aspects/provides/home-manager.nix` — move ctx provides to stages
- Modify: `modules/aspects/provides/hjem.nix` — move ctx provides to stages
- Modify: `modules/aspects/provides/maid.nix` — move ctx provides to stages
- Modify: `modules/aspects/provides/wsl.nix` — move ctx provides to stages
- Modify: `modules/outputs/flakeSystemOutputs.nix` — move provides to stages
- Modify: `modules/outputs/osConfigurations.nix` — move provides to stages
- Modify: `modules/outputs/hmConfigurations.nix` — move provides to stages

**Acceptance Criteria:**
- [ ] No `ctx.*.provides` declarations remain in production code
- [ ] All provides live on `den.stages.*`
- [ ] `resolveStage` reads provides from stages (already implemented in Task 0)
- [ ] `nix develop -c just ci` passes

**Verify:** `nix develop -c just ci`

**Steps:**

- [ ] **Step 1: Move each provides declaration**

For each file, change `ctx.X.provides.Y = fn` → `den.stages.X.provides.Y = fn`.

Note: some stages may not have leaf detection triggered yet (the stageNodeKeys issue). Adding `provides` may require also adding `includes = [];` for leaf detection. Check if the stage already has includes from Phase 3a migration.

- [ ] **Step 2: Format, test, commit**

```bash
nix develop -c just fmt
nix develop -c just ci
git -c core.hooksPath=/dev/null commit -m "refactor: move ctx provides to den.stages"
```

---

### Task 3: Remove ctx into declarations

**Goal:** Remove all `into` declarations from ctx nodes. Relationships handle all transitions now, and ctxApply is no longer used (resolveStage doesn't read `into`).

**Files:**
- Modify: `modules/context/host.nix` — remove into.user, into.default
- Modify: `modules/context/user.nix` — remove into.default
- Modify: `modules/aspects/provides/home-manager.nix` — remove into declarations
- Modify: `modules/aspects/provides/hjem.nix` — remove into
- Modify: `modules/aspects/provides/maid.nix` — remove into
- Modify: `modules/aspects/provides/wsl.nix` — remove into
- Modify: `modules/outputs/flakeSystemOutputs.nix` — remove into
- Modify: `modules/outputs/osConfigurations.nix` — remove into
- Modify: `modules/outputs/hmConfigurations.nix` — remove into
- Modify: Template modules with into declarations

**Acceptance Criteria:**
- [ ] No `ctx.*.into` or `den.ctx.*.into` declarations remain
- [ ] `nix develop -c just ci` passes — relationships handle all transitions

**Verify:** `nix develop -c just ci`

---

### Task 4: Migrate CI test fixtures

**Goal:** Update CI test fixtures that define custom ctx nodes with into/provides to use relationships + stages.

**Files:**
- Modify: 20+ files in `templates/ci/modules/features/`

**Acceptance Criteria:**
- [ ] No `den.ctx.*.into` or `den.ctx.*.provides` in CI tests
- [ ] Tests use `den.relationships` for transitions and `den.stages` for provides/behavior
- [ ] Obsolete tests (testing deprecated ctx features) are deleted or rewritten
- [ ] `nix develop -c just ci` passes

**Verify:** `nix develop -c just ci`

**Steps:**

- [ ] **Step 1: Identify all ctx into/provides in CI tests**

```bash
grep -rn 'ctx\.\(.*\)\.\(into\|provides\)' templates/ci/ --include='*.nix' | grep -v '# '
```

- [ ] **Step 2: Migrate in batches of ~5 files, testing after each batch**

For each file:
- `den.ctx.X.into.Y = fn` → `den.relationships.X-to-Y = { from = "X"; to = "Y"; resolve = fn; }`
  - Remember: resolve functions MUST guard context shape (`builtins.isAttrs`, key checks)
- `den.ctx.X.provides.Y = fn` → `den.stages.X.provides.Y = fn`
- `den.ctx.X { args }` calls → `den.lib.resolveStage.resolveStage "X" args`

- [ ] **Step 3: Delete obsolete test files**

Files that test ctxApply-specific behavior (e.g., `fx-ctx-apply.nix`) may be obsolete. Review and delete if they test removed functionality.

---

### Task 5: Delete ctx infrastructure

**Goal:** Remove all ctx infrastructure files and the `den.ctx` option.

**Files:**
- Delete: `nix/lib/ctx-types.nix`
- Delete: `nix/lib/ctx-apply.nix`
- Delete: `nix/nixModule/ctx.nix`
- Delete: `modules/context/host.nix` (should be empty by now)
- Delete: `modules/context/user.nix` (should be empty by now)
- Delete: `modules/context/perHost-perUser.nix`
- Modify: `nix/lib/default.nix` — remove ctxApply, ctxTypes entries
- Modify: `nix/nixModule/default.nix` — remove ctx.nix import
- Modify: `nix/lib/aspects/fx/handlers/transition.nix` — remove `den.ctx` lookup (keep `den.stages` only)
- Modify: `nix/lib/namespace-types.nix` — remove ctx option
- Modify: `nix/lib/resolve-stage.nix` — remove ctx fallback (stages are now canonical)

**Acceptance Criteria:**
- [ ] `den.ctx` option does not exist
- [ ] No ctx infrastructure files remain
- [ ] `grep -rn 'den\.ctx' nix/ modules/ --include='*.nix' | grep -v '# '` returns empty
- [ ] `nix develop -c just ci` passes

**Verify:** `nix develop -c just ci`

---

### Task 6: Final verification and push

**Goal:** Full grep verification, test suite, push.

**Acceptance Criteria:**
- [ ] `grep -rn 'den\.ctx' nix/ modules/ templates/ --include='*.nix' | grep -v '# ' | grep -v 'docs/'` returns empty
- [ ] `nix develop -c just fmt` produces no changes
- [ ] `nix develop -c just ci` passes
- [ ] Branch pushed to `sini/feat/rm-legacy`

**Verify:** grep + `nix develop -c just ci`

```bash
grep -rn 'den\.ctx' nix/ modules/ templates/ --include='*.nix' | grep -v '# ' | grep -v 'docs/'
nix develop -c just fmt
nix develop -c just ci
git push sini feat/rm-legacy
```
