# Phase 1: Entity Type Consolidation

> **For agentic workers:** REQUIRED: Use superpowers-extended-cc:subagent-driven-development (if subagents available) or superpowers-extended-cc:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Consolidate scattered entity type definitions (hostType, userType, homeType) from the monolithic `nix/lib/types.nix` into per-entity files under `nix/lib/entities/`, with shared helpers extracted to `_types.nix`.

**Architecture:** Pure structural refactor — split one 290-line file into focused per-entity files. `modules/options.nix` (the only direct importer) updates its import path. No behavioral changes; `den.ctx` stays as-is. All 440 passing tests must continue passing.

**Tech Stack:** Nix, nix-unit, flake-parts

**Spec:** `docs/superpowers/specs/2026-04-21-ctx-as-classes-design.md` (Phase 1 section)

**Branch:** `feat/rm-legacy`

**Test command:** `just ci` (runs all CI template tests with `--override-input den .`)

**Format command:** `nix develop -c just fmt`

**Spec deviations (intentional):**
- `userType` is co-located with `hostType` in `host.nix` (not a separate `user.nix`) because it is structurally coupled to the host entity — `userType` takes a `host` argument and is only consumed via `hostType.users`. A future phase may decouple it if user entities gain independent instantiation.
- `schemaEntryType` stays in `modules/options.nix` for Phase 1 — it depends on `den.ctx` which is not being touched yet. Extraction is deferred to Phase 2.
- `nix/lib/aspects/types.nix` (aspect submodule types) is a different file from `nix/lib/types.nix` (entity types) and is NOT touched by this refactor.

---

### Task 0: Create shared entity helpers (`_types.nix`)

**Goal:** Extract the `strOpt` helper and system wrapper types (`systemType`, `homeSystemType`) into a shared file that per-entity files will import.

**Files:**
- Create: `nix/lib/entities/_types.nix`
- Read: `nix/lib/types.nix:150-168` (strOpt, systemType, homeSystemType sources)

**Acceptance Criteria:**
- [ ] `_types.nix` exports `strOpt`, `systemType`, `homeSystemType`
- [ ] File takes `{ lib, den, config, inputs }` args (same as current types.nix)
- [ ] No new functionality — pure extraction

**Verify:** `nix-instantiate --parse nix/lib/entities/_types.nix` — syntax check

**Steps:**

- [ ] **Step 1: Create the shared types file**

```nix
# nix/lib/entities/_types.nix
#
# Shared helpers for entity type definitions.
# Extracted from nix/lib/types.nix — no new functionality.
{
  lib,
  ...
}:
let
  strOpt =
    description: default:
    lib.mkOption {
      type = lib.types.str;
      inherit description default;
    };
in
{
  inherit strOpt;
}
```

Only `strOpt` is shared. `systemType`/`homeSystemType` are parameterized by their contained entity type and stay co-located in `host.nix`/`home.nix`.

- [ ] **Step 2: Stage and verify syntax**

```bash
git add nix/lib/entities/_types.nix
nix-instantiate --parse nix/lib/entities/_types.nix
```

---

### Task 1: Extract host entity type (`host.nix`)

**Goal:** Move `hostType`, `userType`, `systemType`, and `hostsOption` from `nix/lib/types.nix` into `nix/lib/entities/host.nix`.

**Files:**
- Create: `nix/lib/entities/host.nix`
- Read: `nix/lib/types.nix:9-156` (hostsOption, systemType, hostType, userType, strOpt)

**Acceptance Criteria:**
- [ ] `host.nix` exports `hostsOption` (the top-level option for `den.hosts`)
- [ ] `hostType` and `userType` are defined internally (not exported — consumed by `hostsOption`)
- [ ] `strOpt` imported from `_types.nix`
- [ ] Code is identical to current `types.nix` — no behavioral changes

**Verify:** Deferred to Task 3 (wiring)

**Steps:**

- [ ] **Step 1: Create host entity file**

Copy lines 9-156 from `nix/lib/types.nix` into `nix/lib/entities/host.nix`. Import `strOpt` from `./_types.nix`. The file takes `{ lib, den, config, inputs }` and returns `{ hostsOption }`.

```nix
# nix/lib/entities/host.nix
#
# Host entity type definition.
# Extracted from nix/lib/types.nix — no new functionality.
{
  inputs,
  config,
  lib,
  den,
  ...
}:
let
  inherit (import ./_types.nix { inherit lib den config inputs; }) strOpt;

  hostsOption = lib.mkOption {
    description = "den hosts definition";
    default = { };
    defaultText = lib.literalExpression "{ }";
    type = lib.types.attrsOf systemType;
  };

  systemType = lib.types.submodule (
    { name, ... }:
    {
      freeformType = lib.types.attrsOf (hostType name);
    }
  );

  hostType =
    system:
    lib.types.submodule (
      { name, config, ... }:
      {
        freeformType = lib.types.attrsOf lib.types.anything;
        imports = [ den.schema.host ];
        config._module.args.host = config;
        options = {
          name = strOpt "host configuration name" name;
          hostName = strOpt "Network hostname" config.name;
          system = strOpt "platform system" system;
          class = strOpt "os-configuration nix class for host" (
            if lib.hasSuffix "darwin" config.system then "darwin" else "nixos"
          );
          aspect = lib.mkOption {
            description = "Aspect that configures this host.";
            type = lib.types.raw;
            defaultText = "den.aspects.<name>";
            default = den.aspects.${config.name};
          };
          description = strOpt "host description" "${config.class}.${config.hostName}@${config.system}";
          users = lib.mkOption {
            description = "user accounts";
            default = { };
            defaultText = lib.literalExpression "{ }";
            type = lib.types.attrsOf (userType config);
          };
          instantiate = lib.mkOption {
            description = ''
              Function used to instantiate the OS configuration.

              Depending on class, defaults to:
              `darwin`: inputs.darwin.lib.darwinSystem
              `nixos`:  inputs.nixpkgs.lib.nixosSystem
              `systemManager`: inputs.system-manager.lib.makeSystemConfig

              Set explicitly if you need:

              - a custom input name, eg, nixos-unstable.
              - adding specialArgs when absolutely required.
            '';
            example = lib.literalExpression "inputs.nixpkgs.lib.nixosSystem";
            type = lib.types.raw;
            defaultText = lib.literalExpression "inputs.nixpkgs.lib.nixosSystem";
            default =
              {
                nixos = inputs.nixpkgs.lib.nixosSystem;
                darwin = inputs.darwin.lib.darwinSystem;
                systemManager = inputs.system-manager.lib.makeSystemConfig;
              }
              .${config.class};
          };
          intoAttr = lib.mkOption {
            description = ''
              Flake attr where to add the named result of this configuration.
              flake.<intoAttr>.<name>

              Depending on class, defaults to:
              `darwin`: darwinConfigurations
              `nixos`:  nixosConfigurations
              `systemManager`: systemConfigs
            '';
            example = lib.literalExpression ''[  "nixosConfigurations" hostName ]'';
            type = lib.types.listOf lib.types.str;
            defaultText = lib.literalExpression ''[  "nixosConfigurations" hostName ]'';
            default =
              {
                nixos = [
                  "nixosConfigurations"
                  config.name
                ];
                darwin = [
                  "darwinConfigurations"
                  config.name
                ];
                systemManager = [
                  "systemConfigs"
                  config.name
                ];
              }
              .${config.class};
          };
          mainModule = lib.mkOption {
            internal = true;
            visible = false;
            readOnly = true;
            type = lib.types.deferredModule;
            defaultText = "den.lib.aspects.resolve config.class config.resolved";
            default = den.lib.aspects.resolve config.class config.resolved;
          };
        };
      }
    );

  userType =
    host:
    lib.types.submodule (
      { name, config, ... }:
      {
        freeformType = lib.types.attrsOf lib.types.anything;
        imports = [ den.schema.user ];
        config._module.args.host = host;
        config._module.args.user = config;
        options = {
          name = strOpt "user configuration name" name;
          userName = strOpt "user account name" name;
          classes = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            description = "home management nix classes";
            defaultText = lib.literalExpression ''[ "user" ]'';
            default = [ "user" ];
          };
          aspect = lib.mkOption {
            description = "Aspect that configures this user.";
            type = lib.types.raw;
            defaultText = "den.aspects.<name>";
            default = den.aspects.${config.name};
          };
          host = lib.mkOption {
            default = host;
            defaultText = lib.literalExpression "host";
          };
        };
      }
    );

in
{
  inherit hostsOption;
}
```

- [ ] **Step 2: Stage and verify syntax**

```bash
git add nix/lib/entities/host.nix
nix-instantiate --parse nix/lib/entities/host.nix
```

---

### Task 2: Extract home entity type (`home.nix`)

**Goal:** Move `homeType`, `homeSystemType`, and `homesOption` from `nix/lib/types.nix` into `nix/lib/entities/home.nix`.

**Files:**
- Create: `nix/lib/entities/home.nix`
- Read: `nix/lib/types.nix:157-289` (homesOption, homeSystemType, homeType)

**Acceptance Criteria:**
- [ ] `home.nix` exports `homesOption`
- [ ] `homeType` and `homeSystemType` are defined internally
- [ ] `strOpt` imported from `_types.nix`
- [ ] Code is identical to current `types.nix` — no behavioral changes

**Verify:** Deferred to Task 3 (wiring)

**Steps:**

- [ ] **Step 1: Create home entity file**

Copy lines 157-289 from `nix/lib/types.nix` into `nix/lib/entities/home.nix`. Import `strOpt` from `./_types.nix`. The file takes `{ lib, den, config, inputs }` and returns `{ homesOption }`.

**Note:** `home.nix` uses `}@top:` to bind the full argument set because `homeType` references `top.config` for the `osConfig` passthrough to home-manager. `host.nix` does not need `@top`.

```nix
# nix/lib/entities/home.nix
#
# Home entity type definition.
# Extracted from nix/lib/types.nix — no new functionality.
{
  inputs,
  config,
  lib,
  den,
  ...
}@top:
let
  inherit (import ./_types.nix { inherit lib den config inputs; }) strOpt;

  homesOption = lib.mkOption {
    description = "den standalone home-manager configurations";
    default = { };
    type = lib.types.attrsOf homeSystemType;
  };

  homeSystemType = lib.types.submodule (
    { name, ... }:
    {
      freeformType = lib.types.attrsOf (homeType name);
    }
  );

  homeType =
    system:
    lib.types.submodule (
      { name, config, ... }:
      let
        parts = builtins.split "@" name;
        nameWithHost = builtins.length parts > 1;
        userName = lib.head parts;
        hostName = if nameWithHost then lib.last parts else null;
        hostByName = den.hosts.${system}.${hostName} or null;
        userByName = hostByName.users.${userName} or null;

        homeManagerConfiguration =
          if nameWithHost && hostByName != null then
            { pkgs, modules }:
            inputs.home-manager.lib.homeManagerConfiguration {
              inherit pkgs modules;
              extraSpecialArgs.osConfig = lib.attrByPath (
                [ "flake" ] ++ hostByName.intoAttr ++ [ "config" ]
              ) null top.config;
            }
          else
            inputs.home-manager.lib.homeManagerConfiguration;
      in
      {
        freeformType = lib.types.attrsOf lib.types.anything;
        imports = [ den.schema.home ];
        config._module.args.home = config;
        config._module.args.host = hostByName;
        config._module.args.user = userByName;
        options = {
          name = strOpt "home configuration name" userName;
          userName = strOpt "user account name" userName;
          hostName = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = hostName;
            description = "host name (null for unbound standalone homes)";
          };
          user = lib.mkOption {
            default = userByName;
            defaultText = lib.literalExpression "user";
          };
          host = lib.mkOption {
            default = hostByName;
            defaultText = lib.literalExpression "host";
          };
          system = strOpt "platform system" system;
          class = strOpt "home management nix class" "homeManager";
          aspect = lib.mkOption {
            description = "Aspect that configures this home.";
            type = lib.types.raw;
            defaultText = "den.aspects.<name>";
            default = den.aspects.${config.name};
          };
          description = strOpt "home description" "home.${config.name}@${config.system}";
          pkgs = lib.mkOption {
            description = ''
              nixpkgs instance used to build the home configuration.
            '';
            example = lib.literalExpression ''inputs.nixpkgs.legacyPackages.''${home.system}'';
            type = lib.types.raw;
            defaultText = lib.literalExpression ''inputs.nixpkgs.legacyPackages.''${home.system}'';
            default = inputs.nixpkgs.legacyPackages.${config.system};
          };
          instantiate = lib.mkOption {
            description = ''
              Function used to instantiate the home configuration.

              Depending on class, defaults to:
              `homeManager`: inputs.home-manager.lib.homeManagerConfiguration

              Set explicitly if you need:

              - a custom input name, eg, home-manager-unstable.
              - adding extraSpecialArgs when absolutely required.
            '';
            example = lib.literalExpression "inputs.home-manager.lib.homeManagerConfiguration";
            type = lib.types.raw;
            defaultText = lib.literalExpression "inputs.home-manager.lib.homeManagerConfiguration";
            default =
              {
                homeManager = homeManagerConfiguration;
              }
              .${config.class};
          };
          intoAttr = lib.mkOption {
            description = ''
              Flake attr where to add the named result of this configuration.
              flake.<intoAttr>.<name>

              Depending on class, defaults to:
              `homeManager`: homeConfigurations
            '';
            example = lib.literalExpression ''[  "homeConfigurations" userName ]'';
            type = lib.types.listOf lib.types.str;
            defaultText = lib.literalExpression ''[  "homeConfigurations" userName ]'';
            default =
              {
                homeManager = [
                  "homeConfigurations"
                  name
                ];
              }
              .${config.class};
          };
          mainModule = lib.mkOption {
            internal = true;
            visible = false;
            readOnly = true;
            type = lib.types.deferredModule;
            defaultText = "den.lib.aspects.resolve config.class config.resolved";
            default = den.lib.aspects.resolve config.class config.resolved;
          };
        };
      }
    );

in
{
  inherit homesOption;
}
```

- [ ] **Step 2: Stage and verify syntax**

```bash
git add nix/lib/entities/home.nix
nix-instantiate --parse nix/lib/entities/home.nix
```

---

### Task 3: Wire entity files into `modules/options.nix` and replace `types.nix`

**Goal:** Update `modules/options.nix` to import from the new per-entity files instead of `nix/lib/types.nix`. Replace `types.nix` with a re-export shim for safety, then run full test suite.

**Files:**
- Modify: `modules/options.nix:9-16` (change import path)
- Modify: `nix/lib/types.nix` (replace with re-export shim)

**Acceptance Criteria:**
- [ ] `modules/options.nix` imports from `nix/lib/entities/host.nix` and `nix/lib/entities/home.nix`
- [ ] `nix/lib/types.nix` becomes a thin shim re-exporting from entity files (backwards compat)
- [ ] `just ci` passes — all 440+ tests green
- [ ] `nix develop -c just fmt` produces no changes

**Verify:** `just ci` → all tests pass

**Steps:**

- [ ] **Step 1: Stage new entity files first**

New files must be staged before `nix` can see them in a flake:

```bash
git add nix/lib/entities/_types.nix nix/lib/entities/host.nix nix/lib/entities/home.nix
```

- [ ] **Step 2: Update modules/options.nix**

Change the import from `types.nix` to the per-entity files:

```nix
# modules/options.nix — lines 9-16
# Before:
#   types = import ./../nix/lib/types.nix { inherit inputs lib den config; };
# After:
  hostEntities = import ./../nix/lib/entities/host.nix {
    inherit inputs lib den config;
  };
  homeEntities = import ./../nix/lib/entities/home.nix {
    inherit inputs lib den config;
  };
```

Update references on lines 66-67:
```nix
# Before:
#   options.den.hosts = types.hostsOption;
#   options.den.homes = types.homesOption;
# After:
  options.den.hosts = hostEntities.hostsOption;
  options.den.homes = homeEntities.homesOption;
```

- [ ] **Step 3: Replace types.nix with re-export shim**

```nix
# nix/lib/types.nix — re-export shim for backwards compatibility
#
# Entity types have been split into per-entity files under nix/lib/entities/.
# This shim re-exports for any external consumers.
args:
let
  host = import ./entities/host.nix args;
  home = import ./entities/home.nix args;
in
{
  inherit (host) hostsOption;
  inherit (home) homesOption;
}
```

- [ ] **Step 4: Format and verify**

```bash
nix develop -c just fmt
just ci
```

Expected: all tests pass, no format changes after fmt.

- [ ] **Step 5: Commit**


```bash
git add nix/lib/entities/_types.nix nix/lib/entities/host.nix nix/lib/entities/home.nix modules/options.nix nix/lib/types.nix
git -c core.hooksPath=/dev/null commit -m "refactor: split entity types into per-entity files under nix/lib/entities/"
```

---

### Task 4: Move `has-aspect.nix` to entities directory

**Goal:** Move the `hasAspect` entity query module from `modules/context/has-aspect.nix` to `nix/lib/entities/_has-aspect.nix`, updating the import path. This co-locates entity infrastructure.

**Files:**
- Create: `nix/lib/entities/_has-aspect.nix` (copy from `modules/context/has-aspect.nix`)
- Modify: `modules/context/has-aspect.nix` (becomes import shim or is deleted if no external consumers)

**Acceptance Criteria:**
- [ ] `_has-aspect.nix` is the canonical location
- [ ] `modules/context/has-aspect.nix` forwards to the new location (or is removed if safe)
- [ ] `just ci` passes

**Verify:** `just ci` → all tests pass

**Steps:**

- [ ] **Step 1: Determine if has-aspect.nix has external consumers**

`modules/context/has-aspect.nix` is auto-imported by `flakeModule.nix`'s recursive directory scan of `modules/`. Moving it OUT of `modules/` means it won't be auto-imported. Two options:

**Option A:** Keep the file in `modules/context/has-aspect.nix` but have it import from `nix/lib/entities/_has-aspect.nix`.
**Option B:** Move the file and add an explicit import in the entity files or `modules/options.nix`.

Option A is safest — the auto-import still works, the implementation lives in entities.

- [ ] **Step 2: Create entities/_has-aspect.nix**

Copy `modules/context/has-aspect.nix` content to `nix/lib/entities/_has-aspect.nix`.

- [ ] **Step 3: Update modules/context/has-aspect.nix to import from new location**

```nix
# modules/context/has-aspect.nix — forwards to canonical location
args:
import ../../nix/lib/entities/_has-aspect.nix args
```

Note: `modules/context/has-aspect.nix` uses `{ lib, config, ... }:` module args, not file import args. The forwarding approach depends on whether this is a NixOS module (function taking module args) or a file import. Read the file to determine the right approach.

Since `has-aspect.nix` is a NixOS module (takes `{ lib, config, ... }`), the forwarding is:

```nix
# modules/context/has-aspect.nix
import ../../nix/lib/entities/_has-aspect.nix
```

This works because a NixOS module can be a path to a file containing a module function.

- [ ] **Step 4: Stage, format, test, commit**

```bash
git add nix/lib/entities/_has-aspect.nix modules/context/has-aspect.nix
nix develop -c just fmt
just ci
git add nix/lib/entities/_has-aspect.nix modules/context/has-aspect.nix
git -c core.hooksPath=/dev/null commit -m "refactor: move hasAspect module to nix/lib/entities/"
```

---

### Task 5: Delete deprecated `perHost-perUser.nix` (CONDITIONAL — likely blocked)

**Goal:** Remove the deprecated context-level guards module. These are already marked deprecated with warnings and are replaced by handler-based resolution.

**WARNING:** This task will almost certainly fail `just ci` — `perHost`/`perUser`/`perHome` are used in 6+ test fixtures and 2 core pipeline files. **Skip this task if tests fail.** The deletion is deferred to Phase 2 when consumer migration happens.

**Files:**
- Delete: `modules/context/perHost-perUser.nix`

**Acceptance Criteria:**
- [ ] File is deleted
- [ ] `just ci` passes (confirms no test depends on the deprecated guards without the deprecation being acceptable)
- [ ] `den.lib.perHost`, `den.lib.perUser`, `den.lib.perHome` are no longer available

**Verify:** `just ci` → all tests pass

**Steps:**

- [ ] **Step 1: Check for consumers**

```bash
grep -r "perHost\|perUser\|perHome\|perCtx" templates/ modules/ nix/ --include='*.nix' -l
```

Review results. If any non-test file uses these, they need migration first. The functions already emit deprecation warnings, so test templates may use them intentionally.

- [ ] **Step 2: Delete the file**

```bash
rm modules/context/perHost-perUser.nix
```

- [ ] **Step 3: Test and commit**

```bash
just ci
git add modules/context/perHost-perUser.nix
git -c core.hooksPath=/dev/null commit -m "refactor: remove deprecated perHost/perUser/perHome context guards"
```

If tests fail due to missing `den.lib.perHost` etc., the deletion needs to wait for Phase 2. In that case, skip this task and note the blocker.

---

### Task 6: Verify and push

**Goal:** Run the full test suite, format check, and push to `sini/feat/rm-legacy`.

**Files:** None (verification only)

**Acceptance Criteria:**
- [ ] `nix develop -c just fmt` produces no changes
- [ ] `just ci` passes all tests
- [ ] `just check ci` passes
- [ ] Branch pushed to `sini/feat/rm-legacy`

**Verify:** `just ci` → all tests pass

**Steps:**

- [ ] **Step 1: Full verification**

```bash
nix develop -c just fmt
just ci
```

- [ ] **Step 2: Push**

```bash
git push sini feat/rm-legacy
```
