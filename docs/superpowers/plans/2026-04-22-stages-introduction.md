# Phase 2a: Introduce den.stages

> **For agentic workers:** REQUIRED: Use superpowers-extended-cc:subagent-driven-development (if subagents available) or superpowers-extended-cc:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Introduce `den.stages` as a parallel namespace for scoped behavior, allowing `den.stages.hm-host.nixos.foo = "bar"` alongside existing `den.ctx.hm-host.nixos.foo = "bar"`. The pipeline merges both. No ctx removal yet.

**Architecture:** Add a `stageType` (aspect-shaped submodule without `into`/`__functor`), a `den.stages` option, and modify the transition handler to merge stage behavior into ctx nodes at resolution time. This is additive — `den.ctx` continues to work unchanged. Stages are the first half of the four-way separation (Data/Policies/Stages/Behavior).

**Tech Stack:** Nix, nix-unit, flake-parts

**Spec:** `docs/superpowers/specs/2026-04-21-ctx-as-classes-design.md` (Stages section)

**Branch:** `feat/rm-legacy`

**Test command:** `nix develop -c just ci`

**Format command:** `nix develop -c just fmt`

**Important repo conventions:**
- Stage new files before nix eval: `git add <file>`
- Format before committing: `nix develop -c just fmt`
- Commit with: `git -c core.hooksPath=/dev/null commit -m "..."`
- No Co-Authored-By trailer
- Use `--override-input den .` for template tests

---

### Task 0: Define stageType and den.stages option

**Goal:** Create the `stageType` (like `ctxTreeType` but without `into`/`__functor`) and declare the `den.stages` option.

**Files:**
- Create: `nix/lib/stage-types.nix`
- Create: `nix/nixModule/stages.nix`
- Modify: `nix/lib/default.nix` (add stageTypes to den-lib)

**Acceptance Criteria:**
- [ ] `stageType` is an aspect-shaped submodule (has `name`, `description`, `meta`, `includes`, `provides`, freeform class keys) without `into` or `__functor`
- [ ] `stageTreeType` supports recursive nesting (like `ctxTreeType`) for namespace reuse
- [ ] `den.stages` option is declared with type `lazyAttrsOf stageTreeType`
- [ ] `nix develop -c just ci` passes (additive change, no regressions)

**Verify:** `nix develop -c just ci`

**Steps:**

- [ ] **Step 1: Create `nix/lib/stage-types.nix`**

Model this after `nix/lib/ctx-types.nix` but remove `into`, `__functor`, and `intoCtxType`. The stage submodule imports `aspectType.getSubModules` just like `ctxSubmodule` does — this gives it `name`, `meta`, `includes`, `provides`, and freeform class keys (nixos, darwin, etc.).

The `stageTreeType` uses the same recursive merge pattern as `ctxTreeType`: if any definition has a structural key (`provides`, `_`, `includes`, `_module`), treat it as a leaf (stage node). Otherwise treat it as a namespace (recurse into `lazyAttrsOf stageTreeType`).

Key difference from ctx-types.nix: the structural detection keys do NOT include `into` — stages don't have transitions.

```nix
# nix/lib/stage-types.nix
#
# Stage type definitions. Stages are named scopes for binding behavior
# to policy pipeline stages. Like ctx nodes but without transitions
# (into), callable functor, or provides (which is a policy concern).
{ lib, den, ... }:
let
  stageSubmodule = lib.types.submodule {
    imports = den.lib.aspects.types.aspectType.getSubModules;
    # No options.into — stages don't define transitions
    # No options.__functor — stages aren't callable
    # Disable provides — stages bind behavior, they don't provide to other stages.
    # (provides is inherited from aspectType but should not be used on stages)
  };

  stageTreeType = lib.types.mkOptionType {
    name = "stageTree";
    description = "stage definition or namespace";
    check = lib.isAttrs;
    merge =
      loc: defs:
      let
        # Structural keys that indicate a leaf stage node vs a namespace.
        # Does NOT include "into" (stages have no transitions) or "provides"
        # (stages don't provide to other stages — that's a policy concern).
        stageNodeKeys = [
          "_"
          "includes"
          "_module"
        ];
        hasKey = x: builtins.any (k: x ? ${k}) stageNodeKeys;
        isLeaf = lib.any (d: hasKey d.value) defs;
      in
      if isLeaf then stageSubmodule.merge loc defs
      else (lib.types.lazyAttrsOf stageTreeType).merge loc defs;
    emptyValue = {
      value = { };
    };
  };
in
{
  inherit stageTreeType;
}
```

**Note:** `stageSubmodule` inherits `provides` from `aspectType.getSubModules` but it should not be used — stages bind behavior, they don't provide to other stages. The `provides` option is not removed from the submodule type (would require patching aspectType internals) but is not included in `stageNodeKeys` for leaf detection and is stripped during the transition handler merge. A future cleanup can add `options.provides = lib.mkOption { visible = false; default = {}; };` to hide it.

- [ ] **Step 2: Create `nix/nixModule/stages.nix`**

Declare the `den.stages` option, parallel to `nix/nixModule/ctx.nix`.

```nix
# nix/nixModule/stages.nix
{ den, lib, ... }:
let
  inherit (den.lib.stageTypes) stageTreeType;
in
{
  options.den.stages = lib.mkOption {
    description = "Named scopes for binding behavior to pipeline stages.";
    default = { };
    defaultText = lib.literalExpression "{ }";
    type = lib.types.lazyAttrsOf stageTreeType;
  };
}
```

- [ ] **Step 3: Register stageTypes in `nix/lib/default.nix`**

Add `stageTypes` to the den-lib mapAttrs:

```nix
# In nix/lib/default.nix, add to the mapAttrs block:
stageTypes = ./stage-types.nix;
```

- [ ] **Step 4: Register the module import**

`nix/nixModule/default.nix` uses a manual import list (lines 10-14). Add `./stages.nix`:

```nix
# nix/nixModule/default.nix — add stages.nix to imports list
imports = map (f: import f (args // { den = config.den; })) [
  ./lib.nix
  ./ctx.nix
  ./stages.nix
  ./aspects.nix
];
```

- [ ] **Step 5: Stage, format, test, commit**

```bash
git add nix/lib/stage-types.nix nix/nixModule/stages.nix
nix develop -c just fmt
nix develop -c just ci
git add nix/lib/stage-types.nix nix/nixModule/stages.nix nix/lib/default.nix
git -c core.hooksPath=/dev/null commit -m "feat: add den.stages option type for scoped behavior bindings"
```

---

### Task 1: Merge stages into transition resolution

**Goal:** Modify the transition handler so that when it resolves a target (e.g., `hm-host`), it also looks up `den.stages.hm-host` and merges its behavior into the resolution.

**Files:**
- Modify: `nix/lib/aspects/fx/handlers/transition.nix:109-114`

**Acceptance Criteria:**
- [ ] When transitioning to stage X, behavior from `den.stages.X` is included alongside `den.ctx.X`
- [ ] If `den.stages.X` exists but `den.ctx.X` does not, the stage behavior still resolves
- [ ] If neither exists, behavior is unchanged (tombstone)
- [ ] Existing tests pass — no regressions

**Verify:** `nix develop -c just ci`

**Steps:**

- [ ] **Step 1: Understand the integration point**

In `transition.nix`, `resolveTransition` looks up the target:
```nix
targetAspect = lib.attrByPath transition.path null (den.ctx or { });
```

After this lookup, we also look up stages:
```nix
stageAspect = lib.attrByPath transition.path null (den.stages or { });
```

Then merge: if both exist, merge the stage's includes/class-keys into the target. If only stage exists, use it as the target. If only ctx exists, use it (current behavior).

- [ ] **Step 2: Implement the merge**

The merge needs to combine the ctx node's aspect with the stage's aspect. Since both are aspect-shaped (they have `includes`, `provides`, freeform class keys), the simplest merge is to treat the stage as additional includes on the target.

In `resolveTransition`, after line 114:

```nix
targetAspect = lib.attrByPath transition.path null (den.ctx or { });
stageAspect = lib.attrByPath transition.path null (den.stages or { });
# Merge stage behavior into target. During coexistence (Phase 2a), both
# ctx and stage behavior must be preserved. Stage class keys (nixos, darwin,
# etc.) are wrapped as an additional include — NOT shallow-merged with // —
# because class keys are deferredModules that can't be safely overridden.
effectiveTarget =
  if targetAspect != null && stageAspect != null then
    let
      # Strip structural keys from stage — the rest are class keys
      stageClassAttrs = builtins.removeAttrs stageAspect [
        "includes" "name" "description" "meta" "provides" "_module" "_"
      ];
      # Wrap stage class keys + includes as a single include on the ctx target.
      # This lets the pipeline merge both ctx and stage behavior correctly.
      stageAsInclude = stageClassAttrs // {
        name = "${targetAspect.name or "?"}.stage";
        includes = stageAspect.includes or [ ];
      };
    in
    targetAspect // {
      includes = (targetAspect.includes or [ ]) ++ [ stageAsInclude ];
    }
  else if stageAspect != null then
    stageAspect
  else
    targetAspect;
```

Then use `effectiveTarget` instead of `targetAspect` in the rest of `resolveTransition`.

**Why includes, not `//`?** Class keys are `deferredModule` values. Shallow `//` would silently drop the ctx's class modules in favor of the stage's. Wrapping the stage as an include lets the pipeline resolve both through normal aspect compilation, preserving all behavior from both sources during the coexistence phase.

- [ ] **Step 3: Update the null check**

The existing code checks `if targetAspect == null && crossProvider == null then` (line 167). Update to use `effectiveTarget`:

```nix
if effectiveTarget == null && crossProvider == null then
```

And update `withTarget` (line 219-221):
```nix
withTarget =
  if effectiveTarget != null then
    resolveContextValue currentCtx effectiveTarget innerResults newCtx
  else
    fx.pure innerResults;
```

- [ ] **Step 4: Format, test, commit**

```bash
nix develop -c just fmt
nix develop -c just ci
git add nix/lib/aspects/fx/handlers/transition.nix
git -c core.hooksPath=/dev/null commit -m "feat: merge den.stages behavior into transition resolution"
```

---

### Task 2: Add stage test fixture

**Goal:** Create a test that verifies `den.stages.X` behavior merges into the pipeline alongside `den.ctx.X`.

**Files:**
- Create: `templates/ci/modules/features/stages.nix`

**Acceptance Criteria:**
- [ ] Test defines `den.stages.default.nixos.test-stages-default = true`
- [ ] Test defines `den.stages.user.nixos.test-stages-user = true`
- [ ] Tests verify stage behavior appears in resolved NixOS config
- [ ] Tests pass alongside existing ctx behavior (both coexist)

**Verify:** `nix develop -c nix-unit --override-input den . --flake ./templates/ci#.tests.stages`

**Steps:**

- [ ] **Step 1: Create test fixture**

Read existing test fixtures (e.g., `templates/ci/modules/features/default-includes.nix` or `templates/ci/modules/features/den-default.nix`) to understand the test pattern. Tests define aspects, hosts, users, then assert on resolved NixOS config values.

Create `templates/ci/modules/features/stages.nix` with:
- A `den.stages.default` with a test nixos option
- A `den.stages.user` with a test nixos option (only active at user level)
- Assertions that the stage behavior appears in the host's resolved config
- Assertions that ctx and stage behavior coexist

- [ ] **Step 2: Stage, format, test, commit**

```bash
git add templates/ci/modules/features/stages.nix
nix develop -c just fmt
nix develop -c nix-unit --override-input den . --flake ./templates/ci#.tests.stages
nix develop -c just ci
git add templates/ci/modules/features/stages.nix
git -c core.hooksPath=/dev/null commit -m "test: add stages integration test"
```

---

### Task 3: Add namespace stages support

**Goal:** Verify that `den.ns.X.stages.Y` works for namespace-provided stages (denful batteries). Add test if needed.

**Files:**
- Read: `nix/lib/namespace-types.nix` (check if stages option needs adding)
- Possibly modify: `nix/lib/namespace-types.nix` (add `stages` to namespace type)

**Acceptance Criteria:**
- [ ] `den.ns.X.stages.Y.nixos.foo = "bar"` works in namespace modules
- [ ] Stages from namespaces merge into the pipeline correctly

**Verify:** `nix develop -c just ci`

**Steps:**

- [ ] **Step 1: Read namespace-types.nix**

Check if namespaces already have a `stages` option or if it needs adding (like namespaces have `ctx` and `schema`).

- [ ] **Step 2: Add stages option to namespace type if needed**

Note: `namespace-types.nix` creates per-namespace `ctxTreeType` with a namespace-scoped `ctxApply`. Stages don't need `ctxApply` (no functor), but the `stageTreeType` may need namespace provenance for provider tracking. For Phase 2a, use the top-level `stageTreeType` — provider tracking in namespace stages is deferred.

```nix
options.stages = lib.mkOption {
  description = "namespace stage scopes";
  defaultText = lib.literalExpression "{ }";
  default = { };
  type = lib.types.lazyAttrsOf stageTreeType;
};
```

Also verify that namespace stages get folded into `den.stages` at evaluation time (similar to how namespace ctx gets folded into `den.ctx`). If they don't, the transition handler's `den.stages` lookup won't find namespace-provided stages.

- [ ] **Step 3: Test with namespace fixture, commit**

Check existing namespace tests (e.g., `nested-ctx.nix`, `nested-ctx-providers.nix`) for the pattern. Verify namespace stages work.

```bash
nix develop -c just fmt
nix develop -c just ci
git -c core.hooksPath=/dev/null commit -m "feat: support den.stages in namespaces"
```

---

### Task 4: Verify and push

**Goal:** Run full test suite, format check, and push.

**Files:** None (verification only)

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
