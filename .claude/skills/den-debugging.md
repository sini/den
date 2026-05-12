---

## name: den-debugging description: Systematic debugging workflow for den/nix issues. Use when encountering bug reports, test failures, regressions, or unexpected behavior in den's aspect pipeline, type system, or fx handlers. Also use when a user shares an error or describes broken behavior in their den config. Trigger on phrases like "bug report", "regression", "broken", "doesn't work", "used to work", "last-win", "not merging", "not included", "wrong behavior".

# Den Debugging Workflow

A structured approach to reproducing, isolating, and fixing bugs in den. The core loop is: **understand the report, read the code path, write a failing test, confirm the failure, fix, confirm the fix, check for regressions.**

This workflow exists because den's fx pipeline has layered abstractions (content wrappers, type merges, effect handlers, key classification) where bugs often manifest far from their root cause. Writing a test first anchors your understanding before you touch implementation code.

## Phase 1: Understand the Bug Report

Before reading any code, extract the concrete claims from the report:

- **What the user did** — the nix expressions they wrote, the API surface they used
- **What they expected** — the behavior they consider correct
- **What actually happened** — the observed result (error, wrong value, missing config)
- **What works** — any workaround or alternative path that succeeds (this narrows the search)

If the report contrasts two API paths (e.g., old syntax works but new syntax doesn't), that contrast is your most valuable clue — it tells you exactly where the code paths diverge.

## Phase 2: Trace the Code Path

Read the relevant source files to understand the mechanism. Don't guess — follow the actual code path from the user's nix expression to the pipeline output.

Refer to the entry point table in `CLAUDE.md`'s "Debugging and tracing" section for a mapping of symptoms to source files and specific tracing points in the pipeline handlers.

Use the Explore agent for broad searches when you're unsure which files are involved. Use direct Grep/Read for targeted lookups when you know the function name.

## Phase 3: Write a Failing Test

Write a minimal test that reproduces the bug **before** attempting any fix. This is non-negotiable — it prevents you from "fixing" something that was never broken, and it catches regressions immediately.

### Test location and structure

Tests live in `templates/ci/modules/features/`. Bug regression tests go in `deadbugs/` and follow the naming convention `issue-NNN-short-description.nix` when there's a GitHub issue, or `descriptive-name.nix` otherwise.

### Test template

```nix
# Brief description of the bug being tested.
{
  denTest,
  lib,
  ...
}:
{
  flake.tests.deadbugs.my-bug-name = {

    test-descriptive-name = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        # Set up the minimal den config that triggers the bug
        den.aspects.igloo.something = { ... };

        # Assert on the evaluated NixOS config
        expr = {
          someCheck = igloo.some.config.path == "expected";
        };
        expected = {
          someCheck = true;
        };
      }
    );

  };
}
```

### Key patterns

- **`denTest` args**: `den` (the den module), `igloo` (nixosConfigurations.igloo.config), `tuxHm` (igloo.home-manager.users.tux) are the main ones.
- **Multi-file definitions**: Use `imports` with inline modules to simulate multiple files defining the same path — you can't have duplicate keys in a single nix file.
- **Attribute existence checks**: Use `? attrName` to test presence without crashing on missing attrs.
- **Stage new files**: Run `git add <file>` before nix can evaluate new test files.

### Run the test

```bash
# Single test suite
nix develop -c nix-unit --override-input den . --flake ./templates/ci#.tests.deadbugs.my-bug-name

# With full trace on failure
nix develop -c nix-unit --override-input den . --flake ./templates/ci#.tests.deadbugs.my-bug-name --show-trace
```

Confirm the test fails with the expected symptom before proceeding.

## Phase 4: Implement the Fix

Now that you have a failing test anchoring the expected behavior:

1. **Make the minimal change** that addresses the root cause. Resist the urge to refactor surrounding code.
1. **Run your regression test** to confirm it passes.
1. **Run the existing related tests** to check you haven't broken anything:
   ```bash
   # Run a related test suite
   nix develop -c nix-unit --override-input den . --flake ./templates/ci#.tests.<related-suite>
   ```
1. **If existing tests break**, isolate which part of your change caused it. A useful technique: revert parts of the fix independently and rerun to identify the problematic change.

## Phase 5: Validate

Run the full CI suite before considering the fix complete:

```bash
# Full suite (limit to 4 workers during agent sessions)
nix develop -c just ci

# Specific suite with traces
nix develop -c just ci suite.test
```

The summary line at the end shows pass/fail counts. All tests must pass.

### Format before committing

```bash
nix develop -c just fmt
```

CI will reject unformatted code.

## Debugging Techniques

### When a fix causes regressions

Don't revert everything. Isolate which specific change broke which test:

1. Keep the test files, revert only implementation changes
1. Re-apply changes one at a time, running the broken test after each
1. Once you identify the problematic change, understand _why_ it breaks the other case before trying a different approach

### When the root cause isn't obvious

Look for structural markers that distinguish the working path from the broken path. In den's pipeline, common differentiators:

- `__contentValues` — present on content wrappers from `aspectContentType`, absent on sub-aspects from `emitNestedAspect` and full aspects from `aspectSubmodule`
- `__provider` — tracks the definition path through nested aspects
- `__providesForwarded` — keys forwarded from `provides` onto the aspect
- `__fn` / `__args` — parametric wrappers
- `__scopeHandlers` — context propagation

### When you need to understand data flow

Add `builtins.trace` calls temporarily to see what values flow through the pipeline:

```nix
innerValue = builtins.trace "innerValue keys: ${builtins.toJSON (builtins.attrNames innerValue)}" innerValue;
```

Remove traces before committing. See `CLAUDE.md`'s "Debugging and tracing" section for the most useful tracing points in the pipeline handlers.

### Structured tracing in tests

The `denTest` harness provides a `trace` helper that resolves an aspect tree and returns its structure. Use it to inspect what the pipeline produces without modifying pipeline code:

```nix
test-trace-example = denTest (
  { den, trace, ... }:
  let t = trace "myAspect" den.aspects.myAspect;
  in {
    expr = builtins.length t.imports > 0;
    expected = true;
  }
);
```

This is useful in Phase 3 when you want to verify what the pipeline emits for a given aspect configuration.
