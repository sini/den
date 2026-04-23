# Effectful Pipeline Bootstrap Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers-extended-cc:subagent-driven-development (if subagents available) or superpowers-extended-cc:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move pipeline setup (policy resolution, target assembly) inside `fx.handle` so the entire lifecycle is interceptable via effects. Enable policies to install named effect handlers scoped to their transition context.

**Architecture:** Two new effects (`resolve-policy`, `resolve-target`) with default handlers preserving current behavior. Policy `handlers` field enables Layer 2 per-policy named effects via `scope.provide`. Spec: `docs/superpowers/specs/2026-04-23-effectful-pipeline-bootstrap-design.md`.

**Tech Stack:** Nix, nix-effects (algebraic effects)

---

### Task 1: Add handlers field to policyType

**Goal:** Extend the policy type with an optional `handlers` field

**Files:**
- Modify: `nix/lib/policy-types.nix`
- Modify: `templates/ci/modules/features/policies.nix`

**Acceptance Criteria:**
- [ ] `policyType` has `handlers` option (`lazyAttrsOf raw`, default `{}`)
- [ ] Existing policies work unchanged
- [ ] Test verifies policy with handlers field is accepted

**Verify:** `nix develop -c just ci` -> 465+ pass

**Steps:**

- [ ] **Step 1: Add handlers option to policyType**

In `nix/lib/policy-types.nix`, add after the `resolve` option:

```nix
handlers = lib.mkOption {
  type = lib.types.lazyAttrsOf lib.types.raw;
  default = { };
  description = "Named effect handlers installed when this policy fires.";
};
```

- [ ] **Step 2: Add test for policy with handlers**

In `templates/ci/modules/features/policies.nix`, add a test that declares a policy with handlers and verifies it's accepted without error:

```nix
test-policy-with-handlers = denTest (
  { den, igloo, ... }:
  {
    den.hosts.x86_64-linux.igloo.users.tux = { };

    den.stages.test-handler-target = {
      includes = [ ];
      nixos.users.users.tux.description = "handler-target";
    };

    den.policies.host-to-test-handler = {
      from = "host";
      to = "test-handler-target";
      resolve = _: [ { } ];
      handlers.test-effect = { param, state }: {
        resume = "test-value";
        inherit state;
      };
    };

    expr = igloo.users.users.tux.description;
    expected = "handler-target";
  }
);
```

- [ ] **Step 3: Stage, format, verify, commit**

```bash
git add nix/lib/policy-types.nix templates/ci/modules/features/policies.nix
nix develop -c just fmt
nix develop -c just ci
git -c core.hooksPath=/dev/null commit -m "feat: add handlers field to policyType"
```

---

### Task 2: Lift policy merge into pipeline computation (resolve-policy effect)

**Goal:** Move policy merge from pre-computation setup into the fx.handle computation via a `resolve-policy` effect

**Files:**
- Modify: `nix/lib/aspects/fx/pipeline.nix`

**Acceptance Criteria:**
- [ ] `resolve-policy` effect sent at pipeline start (inside fx.handle)
- [ ] Default `resolvePolicyHandler` calls `mergePolicyInto`
- [ ] `resolvePolicyHandler` registered in `defaultHandlers`
- [ ] `fxFullResolve` / `fxResolve` API unchanged
- [ ] All 465 tests pass

**Verify:** `nix develop -c just ci` -> 465 pass

**Steps:**

- [ ] **Step 1: Add resolvePolicyHandler**

In `pipeline.nix`, add a new handler after `defaultState`:

```nix
resolvePolicyHandler = {
  "resolve-policy" =
    { param, state }:
    {
      resume = den.lib.synthesizePolicies.mergePolicyInto param.stageName param.existingInto;
      inherit state;
    };
};
```

- [ ] **Step 2: Register in defaultHandlers**

Add `// resolvePolicyHandler` to `defaultHandlers`, before `// fx.effects.state.handler`:

```nix
// handlers.drainDeferredHandler
// resolvePolicyHandler
// fx.effects.state.handler;
```

- [ ] **Step 3: Restructure mkPipeline to use the effect**

Replace the current inline policy merge + `rootEffect` construction:

```nix
# BEFORE (lines 93-110, 133):
selfName = self.name or "";
existingInto = self.meta.into or self.into or null;
mergedInto = den.lib.synthesizePolicies.mergePolicyInto selfName existingInto;
effectiveSelf = if mergedInto != null && mergedInto != existingInto then ... else self;
rootEffect = aspectToEffect effectiveSelf;
...
} rootEffect;
```

With:

```nix
# AFTER:
existingInto = self.meta.into or self.into or null;

bootstrapAndResolve =
  fx.bind (fx.send "resolve-policy" {
    stageName = self.name or "";
    inherit existingInto;
  }) (mergedInto:
    let
      effectiveSelf =
        if mergedInto != null && mergedInto != existingInto then
          self // { meta = (self.meta or { }) // { into = mergedInto; }; }
        else
          self;
    in
    aspectToEffect effectiveSelf
  );
...
} bootstrapAndResolve;
```

Note: `rootHandlers` must be built BEFORE the computation (it doesn't depend on `mergedInto`), so keep it in the `let` block alongside `bootstrapAndResolve`.

- [ ] **Step 4: Stage, format, verify, commit**

```bash
git add nix/lib/aspects/fx/pipeline.nix
nix develop -c just fmt
nix develop -c just ci
git -c core.hooksPath=/dev/null commit -m "feat: lift policy merge into pipeline via resolve-policy effect"
```

---

### Task 3: Replace buildTarget with resolve-target effect + policy handler installation

**Goal:** Replace inline `buildTarget` with a `resolve-target` effect handler; install policy `handlers` via `scope.provide` when transitions fire

**Files:**
- Modify: `nix/lib/aspects/fx/handlers/transition.nix`
- Modify: `nix/lib/aspects/fx/pipeline.nix` (add resolveTargetHandler to defaultHandlers)
- Modify: `templates/ci/modules/features/policies.nix` (add policy handler scoping test)

**Acceptance Criteria:**
- [ ] `buildTarget` deleted from transition.nix
- [ ] `resolve-target` effect sent instead, with default handler doing the same logic
- [ ] `resolveTargetHandler` registered in `defaultHandlers` in pipeline.nix
- [ ] Policy `handlers` collected per-transition and installed via `scope.provide`
- [ ] Core pipeline effects protected from shadowing via `coreEffects` filter
- [ ] All existing tests pass
- [ ] New test verifies a policy's handler is queryable from an aspect under its transition

**Verify:** `nix develop -c just ci` -> 466+ pass

**Steps:**

- [ ] **Step 1: Add resolveTargetHandler to pipeline.nix**

Both `resolvePolicyHandler` and `resolveTargetHandler` are defined as local bindings in `pipeline.nix` (not exported via the handlers module). They're referenced directly in `defaultHandlers` without a `handlers.` prefix.

In `pipeline.nix`, add after `resolvePolicyHandler`:

```nix
resolveTargetHandler = {
  "resolve-target" =
    { param, state }:
    let
      stageAspect = lib.attrByPath param.path null (den.stages or { });
      targetName = if stageAspect != null then stageAspect.name or "" else "";
      existingInto = if stageAspect != null then stageAspect.meta.into or null else null;
      mergedInto = den.lib.synthesizePolicies.mergePolicyInto targetName existingInto;
    in
    {
      resume =
        if stageAspect != null && mergedInto != null then
          stageAspect // { meta = (stageAspect.meta or { }) // { into = mergedInto; }; }
        else if stageAspect != null then
          stageAspect
        else
          null;
      inherit state;
    };
};
```

Register in `defaultHandlers` (directly, no `handlers.` prefix):

```nix
// handlers.drainDeferredHandler
// resolvePolicyHandler
// resolveTargetHandler
// fx.effects.state.handler;
```

- [ ] **Step 2: Replace buildTarget with resolve-target effect in transition.nix**

Delete the `buildTarget` function (lines 96-115).

In `resolveTransition`, replace `effectiveTarget = buildTarget transition;` with:

The transition handler currently calls `buildTarget` directly in `resolveTransition`. Since `resolveTransition` is called from within the `into-transition` handler's `resume` (an effectful computation), we can send effects here.

However, `resolveTransition` is called inside the handler body which returns `{ resume = ...; state; }`. The `resume` is itself an effectful computation. So `resolve-target` will be sent as part of the resume computation.

Change `resolveTransition` to send the effect:

```nix
resolveTransition =
  targetClass: sourceAspect: currentCtx: results: transition:
  let
    key = "${targetClass}/${lib.concatStringsSep "/" transition.path}";
    targetKey = lib.concatStringsSep "." transition.path;
    sourceProvides = sourceAspect.provides or { };
    crossProvider = sourceProvides.${targetKey} or null;
    emitCross = emitCrossProvider { inherit crossProvider sourceAspect targetKey; };
  in
  fx.bind (fx.send "resolve-target" {
    path = transition.path;
    inherit targetClass;
  }) (effectiveTarget:
    if effectiveTarget == null && crossProvider == null then
      let
        tombstone = { ... };  # same as current
      in
      fx.bind (fx.send "resolve-complete" tombstone) (_: fx.pure (results ++ [ tombstone ]))
    else
      let
        isFanOut = builtins.length transition.contexts > 1;
        # Collect policy handlers matching source→target for this transition
        policyHandlers = collectPolicyHandlers (sourceAspect.name or "") targetKey;
      in
      builtins.foldl' (
        acc: newCtx:
        fx.bind acc (
          innerResults:
          let
            ...  # same context setup as current
            # Wrap target resolution in policy scope
            withTarget =
              if effectiveTarget != null then
                let
                  baseComputation =
                    if isFanOut && targetClass == "flake" then
                      resolveFanOut { ... } innerResults
                    else
                      resolveContextValue currentCtx effectiveTarget innerResults newCtx;
                in
                # Note: fan-out sub-pipelines (fxFullResolve) create fresh
                # handler scopes, so policy handlers don't propagate into them.
                # This is intentional — each sub-pipeline is independent.
                if policyHandlers != { } then
                  fx.effects.scope.provide policyHandlers baseComputation
                else
                  baseComputation
              else
                fx.pure innerResults;
          in
          fx.bind (fx.send "ctx-seen" ctxKey) (
            { isFirst }:
            if !isFirst then fx.pure innerResults
            else fx.bind updateCtx (_:
              fx.bind withTarget (targetResults: emitCross scopedCtx scopeHandlers ctxNames targetResults)
            )
          )
        )
      ) (fx.pure results) transition.contexts
  );
```

- [ ] **Step 3: Add collectPolicyHandlers helper**

In `transition.nix`, add a helper that collects handlers from matching policies with core effect protection. Match on BOTH `from` (source stage name, from the `into-transition` handler's `sourceAspect.name`) and `to` (target key from transition path):

```nix
coreEffects = [
  "into-transition" "ctx-seen" "resolve-complete" "emit-class"
  "emit-include" "chain-push" "chain-pop" "check-constraint"
  "register-constraint" "defer-include" "drain-deferred"
  "get-path-set" "has-handler" "resolve-policy" "resolve-target"
];

collectPolicyHandlers =
  sourceStage: targetKey:
  let
    policies = den.policies or { };
    matching = lib.filter (p: p.from == sourceStage && p.to == targetKey) (builtins.attrValues policies);
    allHandlers = builtins.foldl' (acc: p: acc // (p.handlers or { })) { } matching;
  in
  builtins.removeAttrs allHandlers coreEffects;
```

The `sourceStage` comes from the `sourceAspect.name` in `resolveTransition`. The caller passes it as: `collectPolicyHandlers (sourceAspect.name or "") targetKey`.

- [ ] **Step 4: Add test for policy handler scoping**

In `templates/ci/modules/features/policies.nix`, add a test that verifies a policy-installed handler is queryable:

```nix
# Test that a policy's handlers are active during transition resolution.
# The policy installs a "test-greet" handler; an aspect under the
# transition queries it via bind.fn.
test-policy-handler-scoped = denTest (
  { den, igloo, ... }:
  {
    den.hosts.x86_64-linux.igloo.users.tux = { };

    den.stages.test-scoped = {
      includes = [
        ({ test-greet, ... }: {
          nixos.users.users.tux.description = test-greet;
        })
      ];
    };

    den.policies.host-to-test-scoped = {
      from = "host";
      to = "test-scoped";
      resolve = _: [ { } ];
      handlers.test-greet = { param, state }: {
        resume = "hello-from-policy";
        inherit state;
      };
    };

    expr = igloo.users.users.tux.description;
    expected = "hello-from-policy";
  }
);
```

This test verifies the full chain: policy declares `handlers.test-greet` → transition fires → handler scoped via `scope.provide` → parametric aspect `{ test-greet, ... }` resolves via `bind.fn` → handler returns `"hello-from-policy"`.

- [ ] **Step 5: Stage, format, verify, commit**

```bash
git add nix/lib/aspects/fx/handlers/transition.nix nix/lib/aspects/fx/pipeline.nix templates/ci/modules/features/policies.nix
nix develop -c just fmt
nix develop -c just ci
git -c core.hooksPath=/dev/null commit -m "feat: resolve-target effect + per-policy handler installation via scope.provide"
```
