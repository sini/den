# Phase 3a: Migrate Scoped Behavior from den.ctx to den.stages

> **For agentic workers:** REQUIRED: Use superpowers-extended-cc:subagent-driven-development (if subagents available) or superpowers-extended-cc:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Migrate all `den.ctx.*.includes` and `den.ctx.*.{class-keys}` scoped behavior declarations from `den.ctx` to `den.stages`, reducing ctx surface area and proving the stages system works as a drop-in replacement.

**Architecture:** Mechanical find/replace for core modules and templates. Each `den.ctx.X.includes` becomes `den.stages.X.includes`. CI test fixtures that use ctx scoped behavior are updated alongside. The transition handler already merges both `den.ctx` and `den.stages` (from Phase 2a), so both old and new declarations work during migration — no big-bang cutover needed.

**Tech Stack:** Nix, nix-unit, flake-parts

**Spec:** `docs/superpowers/specs/2026-04-21-ctx-as-classes-design.md` (Phase 3 section, "Expected User Impact")

**Branch:** `feat/rm-legacy`

**Test command:** `nix develop -c just ci`

**Format command:** `nix develop -c just fmt`

**Important repo conventions:**
- Stage new files before nix eval: `git add <file>`
- Format before committing: `nix develop -c just fmt`
- Commit with: `git -c core.hooksPath=/dev/null commit -m "..."`
- No Co-Authored-By trailer
- Use `--override-input den .` for template tests

**Backlog items addressed by this plan:**
- Item 6: Migrate `den.ctx.*` scoped behavior to `den.stages` (25 consumer files)
- Partial item 2: Leaf detection improvement will be evaluated during migration

---

### Task 0: Migrate core module scoped behavior to den.stages

**Goal:** Change all `den.ctx.*.includes` in core modules (`modules/aspects/provides/`) to `den.stages.*.includes`.

**Files:**
- Modify: `modules/aspects/provides/os-class.nix:32`
- Modify: `modules/aspects/provides/os-user.nix:50`
- Modify: `modules/aspects/defaults.nix:7`

**Acceptance Criteria:**
- [ ] `os-class.nix` uses `den.stages.default.includes` instead of `den.ctx.default.includes`
- [ ] `os-user.nix` uses `den.stages.user.includes` instead of `den.ctx.user.includes`
- [ ] `defaults.nix` sets `den.stages.default` instead of `den.ctx.default` (or uses a different approach for the default alias)
- [ ] `nix develop -c just ci` passes — no regressions

**Verify:** `nix develop -c just ci`

**Steps:**

- [ ] **Step 1: Read each file and understand the current usage**

Read the three files to see the exact ctx usage and surrounding context.

- [ ] **Step 2: Migrate os-class.nix**

```nix
# Before (line 32):
den.ctx.default.includes = [ os-class ];
# After:
den.stages.default.includes = [ os-class ];
```

- [ ] **Step 3: Migrate os-user.nix**

```nix
# Before (line 50):
den.ctx.user.includes = [ fwd ];
# After:
den.stages.user.includes = [ fwd ];
```

- [ ] **Step 4: Handle defaults.nix special case**

`modules/aspects/defaults.nix` line 7: `config.den.ctx.default = den.default;`

This assigns the entire `den.default` aspect as a ctx node. Under the new model, `den.default` behavior should flow through `den.stages.default`. But `den.default` is also an aspect (behavior), not just scoped behavior.

The simplest migration: keep `den.ctx.default = den.default` for now (it provides the aspect for transition resolution) AND add `den.stages.default = den.default` so the stage system also sees it. The dual assignment is temporary — full ctx removal (Phase 3b) will remove the ctx assignment.

```nix
# Keep existing:
config.den.ctx.default = den.default;
# Add:
config.den.stages.default = den.default;
```

- [ ] **Step 5: Format, test, commit**

```bash
nix develop -c just fmt
nix develop -c just ci
git add modules/aspects/provides/os-class.nix modules/aspects/provides/os-user.nix modules/aspects/defaults.nix
git -c core.hooksPath=/dev/null commit -m "refactor: migrate core module scoped behavior from den.ctx to den.stages"
```

---

### Task 1: Migrate template scoped behavior to den.stages

**Goal:** Change all `den.ctx.*.includes` in template modules to `den.stages.*.includes`.

**Files:**
- Modify: `templates/default/modules/defaults.nix:10`
- Modify: `templates/noflake/modules/den.nix:35`
- Modify: `templates/microvm/modules/den.nix:20`
- Modify: `templates/flake-parts-modules/modules/den.nix:41`
- Modify: `templates/nvf-standalone/modules/den.nix:13`

**Acceptance Criteria:**
- [ ] All template files use `den.stages.*.includes` instead of `den.ctx.*.includes`
- [ ] `nix develop -c just ci` passes

**Verify:** `nix develop -c just ci`

**Steps:**

- [ ] **Step 1: Read each file and make the replacements**

For each file, change `den.ctx.X.includes` → `den.stages.X.includes`:

| File | Line | Before | After |
|------|------|--------|-------|
| `templates/default/modules/defaults.nix` | 10 | `den.ctx.user.includes` | `den.stages.user.includes` |
| `templates/noflake/modules/den.nix` | 35 | `den.ctx.user.includes` | `den.stages.user.includes` |
| `templates/microvm/modules/den.nix` | 20 | `den.ctx.host.includes` | `den.stages.host.includes` |
| `templates/flake-parts-modules/modules/den.nix` | 41 | `den.ctx.flake-parts.includes` | `den.stages.flake-parts.includes` |
| `templates/nvf-standalone/modules/den.nix` | 13 | `den.ctx.flake-packages.includes` | `den.stages.flake-packages.includes` |

- [ ] **Step 2: Format, test, commit**

```bash
nix develop -c just fmt
nix develop -c just ci
git add templates/default/modules/defaults.nix templates/noflake/modules/den.nix templates/microvm/modules/den.nix templates/flake-parts-modules/modules/den.nix templates/nvf-standalone/modules/den.nix
git -c core.hooksPath=/dev/null commit -m "refactor: migrate template scoped behavior from den.ctx to den.stages"
```

---

### Task 2: Migrate CI test fixture scoped behavior to den.stages

**Goal:** Update CI test fixtures that use `den.ctx.*.includes` or `den.ctx.*.{class-keys}` to use `den.stages` instead.

**Files:**
- Modify: `templates/ci/modules/features/hm-host-isolation.nix` (lines 9, 20)
- Modify: `templates/ci/modules/features/host-propagation.nix` (lines 23, 108-125)
- Modify: `templates/ci/modules/features/has-aspect.nix` (lines 368, 384, 407)
- Modify: `templates/ci/modules/features/define-user.nix` (line 28)
- Modify: Other CI files with `den.ctx.*.funny.names`, `den.ctx.*.includes`

**Acceptance Criteria:**
- [ ] All CI test files use `den.stages.*.includes` and `den.stages.*.{class-keys}` for scoped behavior
- [ ] Tests that were passing before continue to pass
- [ ] No ctx scoped behavior references remain in CI test files (only ctx `into`, `provides`, and calls remain)

**Verify:** `nix develop -c just ci`

**Steps:**

- [ ] **Step 1: Grep for remaining den.ctx scoped behavior in CI tests**

```bash
grep -rn 'den\.ctx\.\(.*\)\.\(includes\|nixos\|darwin\|homeManager\|funny\)' templates/ci/ --include='*.nix'
```

This shows all lines that need migration. Exclude lines that are part of `den.ctx.*.provides.*` or `den.ctx.*.into.*` (those are Phase 3b).

- [ ] **Step 2: Migrate each file**

For each line found, change `den.ctx.X.includes` → `den.stages.X.includes` and `den.ctx.X.funny` → `den.stages.X.funny`, etc.

**Important:** Some test files define custom ctx nodes with BOTH `into` AND scoped behavior (e.g., `custom-ctx.nix` has `den.ctx.bar.funny.names` AND `den.ctx.greeting.into.shout`). For these, migrate ONLY the scoped behavior to stages. Leave the `into` and `provides` on ctx for now.

- [ ] **Step 3: Format, test, commit**

```bash
nix develop -c just fmt
nix develop -c just ci
git add templates/ci/modules/features/*.nix
git -c core.hooksPath=/dev/null commit -m "refactor: migrate CI test scoped behavior from den.ctx to den.stages"
```

---

### Task 3: Verify no scoped behavior remains on den.ctx

**Goal:** Confirm that after migration, NO `den.ctx.*.includes` or `den.ctx.*.{class-keys}` scoped behavior declarations remain anywhere in the codebase (except in docs/specs).

**Files:** None (verification only)

**Acceptance Criteria:**
- [ ] `grep -rn 'den\.ctx\.\(.*\)\.\(includes\|nixos\|darwin\|homeManager\|funny\)' modules/ templates/ nix/ --include='*.nix'` returns only `provides.*` or `into.*` lines (not direct scoped behavior)
- [ ] Exception: `modules/aspects/defaults.nix` may still have `den.ctx.default = den.default` (the alias, not scoped behavior)
- [ ] `nix develop -c just ci` passes

**Verify:** grep + `nix develop -c just ci`

**Steps:**

- [ ] **Step 1: Run the verification grep**

```bash
grep -rn 'den\.ctx\.' modules/ templates/ nix/ --include='*.nix' | grep -v '\.into\.' | grep -v '\.provides\.' | grep -v '# ' | grep -v 'den\.ctx = ' | grep -v 'den\.ctx or ' | grep -v 'den\.ctx\.' | head -50
```

Refine the grep to find any remaining scoped behavior that was missed.

- [ ] **Step 2: Fix any stragglers found**

- [ ] **Step 3: Final test run and push**

```bash
nix develop -c just fmt
nix develop -c just ci
git push sini feat/rm-legacy
```
