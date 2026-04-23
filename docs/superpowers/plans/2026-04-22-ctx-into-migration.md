# Phase 3b: Migrate Core `into` Declarations to `den.relationships`

> **For agentic workers:** REQUIRED: Use superpowers-extended-cc:subagent-driven-development (if subagents available) or superpowers-extended-cc:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Duplicate the core `den.ctx.*.into` declarations as `den.relationships` entries, proving they work alongside the existing ctx system. This is additive — ctx `into` is NOT removed yet.

**Architecture:** For each `into` declaration on a core ctx node, create an equivalent `den.relationships` entry. The pipeline already synthesizes relationships into `into` functions (Phase 2b). By having both, we prove the relationship declarations produce identical results. A follow-up phase removes the ctx `into` declarations once verified.

**Tech Stack:** Nix, nix-unit, flake-parts

**Branch:** `feat/rm-legacy`

**Test command:** `nix develop -c just ci`
**Format command:** `nix develop -c just fmt`

**Conventions:** Stage new files with `git add`, format before commit, commit with `git -c core.hooksPath=/dev/null commit`, no Co-Authored-By trailer.

**Scope boundary:** This plan adds `den.relationships` entries ALONGSIDE existing `den.ctx.*.into`. It does NOT remove ctx `into`, `provides`, ctxApply, or ctx infrastructure. Those are follow-up work.

**Important consideration:** Since the pipeline now synthesizes relationships into `into` functions AND ctx nodes still have their own `into`, the same transitions will fire TWICE — once from the relationship and once from the ctx `into`. The `ctx-seen` dedup handler prevents this from causing duplicate resolution (transitions to the same target path are deduped). However, we should verify this by running tests after each addition.

---

### Task 0: Add core entity relationships (host→user, host→default, user→default)

**Goal:** Create `modules/relationships/core.nix` with the fundamental entity relationships.

**Files:**
- Create: `modules/relationships/core.nix`

**Acceptance Criteria:**
- [ ] `den.relationships.host-to-users` declared with `from = "host"`, `to = "user"`, resolve = host→users fan-out
- [ ] `den.relationships.host-to-default` declared with `from = "host"`, `to = "default"`, resolve = lib.singleton
- [ ] `den.relationships.user-to-default` declared with `from = "user"`, `to = "default"`, resolve = lib.singleton
- [ ] `nix develop -c just ci` passes — dedup prevents duplicate resolution

**Verify:** `nix develop -c just ci`

**Steps:**

- [ ] **Step 1: Create the relationships module**

```nix
# modules/relationships/core.nix
#
# Core entity relationships — the fundamental transitions between entity kinds.
# These duplicate den.ctx.*.into declarations as den.relationships entries.
# Both coexist during migration; ctx-seen dedup prevents double resolution.
{ lib, ... }:
{
  den.relationships = {
    host-to-users = {
      from = "host";
      to = "user";
      resolve = { host }: map (user: { inherit host user; }) (lib.attrValues host.users);
    };
    host-to-default = {
      from = "host";
      to = "default";
      resolve = lib.singleton;
    };
    user-to-default = {
      from = "user";
      to = "default";
      resolve = lib.singleton;
    };
  };
}
```

Note: `home.into.default` is defined in `modules/aspects/provides/home-manager.nix`, not in a context module. Add `home-to-default` in a later task with the home-manager relationships.

- [ ] **Step 2: Stage, format, test, commit**

```bash
git add modules/relationships/core.nix
nix develop -c just fmt
nix develop -c just ci
git add modules/relationships/core.nix
git -c core.hooksPath=/dev/null commit -m "feat: add core entity relationships (host→user, host→default, user→default)"
```

**If tests fail due to duplicate transitions:** The `ctx-seen` handler should dedup. If it doesn't, the relationship synthesis in `pipeline.nix` may need to check for existing `into` targets and skip duplicates. Debug by checking which transitions fire twice.

---

### Task 1: Add flake output relationships

**Goal:** Create `modules/relationships/flake.nix` with the flake output pipeline relationships.

**Files:**
- Create: `modules/relationships/flake.nix`

**Acceptance Criteria:**
- [ ] `den.relationships.flake-to-systems` (flake → per-system fan-out)
- [ ] `den.relationships.flake-system-to-os` (system → per-host fan-out)
- [ ] `den.relationships.flake-system-to-hm` (system → per-home fan-out)
- [ ] Per-output relationships (flake-packages, flake-apps, flake-checks, flake-devShells, flake-legacyPackages)
- [ ] `nix develop -c just ci` passes

**Verify:** `nix develop -c just ci`

**Steps:**

- [ ] **Step 1: Read existing flake output ctx declarations**

Read these files to get the exact `into` functions:
- `modules/outputs/flakeSystemOutputs.nix` — flake.into.flake-system, flake-system.into.flake-*
- `modules/outputs/osConfigurations.nix` — flake-system.into.flake-os
- `modules/outputs/hmConfigurations.nix` — flake-system.into.flake-hm

- [ ] **Step 2: Create relationships module**

Translate each `ctx.*.into.*` into a `den.relationships` entry. The resolve functions reference `den.systems`, `den.hosts`, `den.homes` — these are available as closures from the module args.

```nix
# modules/relationships/flake.nix
{ den, lib, ... }:
{
  den.relationships = {
    flake-to-systems = {
      from = "flake";
      to = "flake-system";
      resolve = _: map (system: { inherit system; }) den.systems;
    };
    flake-system-to-os = {
      from = "flake-system";
      to = "flake-os";
      resolve = { system }:
        map (host: { inherit host; })
          (builtins.attrValues (den.hosts.${system} or { }));
    };
    flake-system-to-hm = {
      from = "flake-system";
      to = "flake-hm";
      resolve = { system }:
        map (home: { inherit home; })
          (builtins.attrValues (den.homes.${system} or { }));
    };
    # Per-output relationships generated from flakeSystemOutputs pattern
    # Read flakeSystemOutputs.nix to get the exact systemOutput function
  };
}
```

Note: The per-output relationships (packages, apps, checks, etc.) are generated dynamically in `flakeSystemOutputs.nix`. Read that file and replicate the pattern.

- [ ] **Step 3: Stage, format, test, commit**

```bash
git add modules/relationships/flake.nix
nix develop -c just fmt
nix develop -c just ci
git add modules/relationships/flake.nix
git -c core.hooksPath=/dev/null commit -m "feat: add flake output relationships"
```

---

### Task 2: Add home environment relationships (hm, hjem, maid, wsl)

**Goal:** Create `modules/relationships/batteries.nix` with relationships generated by `makeHomeEnv` and the WSL conditional.

**Files:**
- Create: `modules/relationships/batteries.nix`

**Acceptance Criteria:**
- [ ] Home-manager relationships: host→hm-host, hm-host→hm-user
- [ ] Hjem relationships: host→hjem-host, hjem-host→hjem-user
- [ ] Maid relationships: host→maid-host, maid-host→maid-user
- [ ] WSL relationship: host→wsl-host (conditional)
- [ ] Home→default relationship
- [ ] `nix develop -c just ci` passes

**Verify:** `nix develop -c just ci`

**Steps:**

- [ ] **Step 1: Read the sources**

Read these files to understand the exact `into` functions:
- `nix/lib/home-env.nix` — `makeHomeEnv` generates `host.into.X-host`, `X-host.into.X-user`
- `modules/aspects/provides/home-manager.nix` — uses makeHomeEnv, also defines `home.into.default`
- `modules/aspects/provides/hjem.nix` — uses makeHomeEnv
- `modules/aspects/provides/maid.nix` — uses makeHomeEnv
- `modules/aspects/provides/wsl.nix` — `host.into.wsl-host` (conditional)

- [ ] **Step 2: Create relationships module**

Extract the `into` logic from each `makeHomeEnv` result and the WSL module into relationship declarations. The resolve functions use the same detection/fan-out logic as the existing `into` functions.

- [ ] **Step 3: Stage, format, test, commit**

```bash
git add modules/relationships/batteries.nix
nix develop -c just fmt
nix develop -c just ci
git add modules/relationships/batteries.nix
git -c core.hooksPath=/dev/null commit -m "feat: add battery relationships (hm, hjem, maid, wsl)"
```

---

### Task 3: Verify dedup and push

**Goal:** Verify that all relationship declarations coexist with ctx `into` without causing duplicate resolution. Push.

**Files:** None (verification only)

**Acceptance Criteria:**
- [ ] `nix develop -c just ci` passes (447+ tests, zero regressions)
- [ ] No duplicate module errors from doubled transitions
- [ ] Format clean
- [ ] Pushed to `sini/feat/rm-legacy`

**Verify:** `nix develop -c just ci`

**Steps:**

- [ ] **Step 1: Run full verification**

```bash
nix develop -c just fmt
nix develop -c just ci
```

If there are any new failures, check if they're caused by transitions firing twice (despite ctx-seen dedup). The dedup tracks by transition path key — if the relationship and ctx `into` produce the same path, only one resolves.

- [ ] **Step 2: Push**

```bash
git push sini feat/rm-legacy
```

---

## Follow-up Work (Phase 3c)

After this plan completes, the remaining work to fully remove `den.ctx`:

1. **Remove ctx `into` declarations** — now redundant with `den.relationships`
2. **Migrate ctx `provides` to stages or make implicit** — self-identity (provides.host) and cross-provides
3. **Replace ctxApply calls** — `den.ctx.host { host = config; }` in outputs + schema + home-env
4. **Delete ctx infrastructure** — ctx-types.nix, ctx-apply.nix, nixModule/ctx.nix
5. **Migrate CI test fixtures** — update tests that define custom ctx into/provides
6. **Delete deprecated files** — modules/context/host.nix, user.nix, perHost-perUser.nix
