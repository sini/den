# Code Cleanup Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers-extended-cc:subagent-driven-development (if subagents available) or superpowers-extended-cc:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Improve code quality across the den fx pipeline by eliminating duplication, decomposing oversized functions, fixing efficiency issues, and cleaning up legacy stragglers.

**Architecture:** Pure refactoring — no behavioral changes. Each task produces identical test results (462/462). Changes target `nix/lib/aspects/` (core pipeline), `nix/lib/forward.nix`, and `modules/` (legacy shims).

**Tech Stack:** Nix, nix-effects (algebraic effects)

---

### Task 1: Extract shared predicates to types.nix

**Goal:** Consolidate 3 duplicated predicates into single exports from types.nix

**Files:**
- Modify: `nix/lib/aspects/types.nix:5-9,26` — export `isSubmoduleFn`, add `isMeaningfulName`
- Modify: `nix/lib/aspects/fx/aspect.nix:136,257-258` — import predicates from types
- Modify: `nix/lib/aspects/fx/handlers/transition.nix:143` — import `isParametricWrapper` from types
- Modify: `nix/lib/aspects/fx/handlers/include.nix:47-53,77-80,232-233` — import predicates from types

**Acceptance Criteria:**
- [ ] `isParametricWrapper` defined only in `types.nix`, imported in `aspect.nix`, `transition.nix`
- [ ] `isSubmoduleFn` exported from `types.nix`, imported in `include.nix`, `aspect.nix`
- [ ] `isMeaningfulName` defined in `types.nix`, imported in `aspect.nix`, `include.nix`
- [ ] All 462 tests pass

**Verify:** `nix develop -c just test` -> 462/462 pass

**Steps:**

- [ ] **Step 1: Add isMeaningfulName to types.nix and export isSubmoduleFn**

In `nix/lib/aspects/types.nix`, `isSubmoduleFn` is already defined (line 5) but not exported. Add `isMeaningfulName` alongside it and export both:

```nix
# After isParametricWrapper (line 26), add:
isMeaningfulName =
  name: name != "<anon>" && name != "<function body>" && !(lib.hasPrefix "[definition " name);
```

Update the export block at the bottom:
```nix
{
  inherit
    aspectsType
    aspectType
    providerType
    parametricType
    isParametricWrapper
    isSubmoduleFn
    isMeaningfulName
    ;
}
```

- [ ] **Step 2: Update aspect.nix to import shared predicates**

At top of `aspect.nix`, add:
```nix
inherit (den.lib.aspects.types) isParametricWrapper isMeaningfulName;
```

Remove inline `isParametricWrapper` at line 136 (replace the binding with usage of the imported one).

Replace lines 257-258 inline `isMeaningful` check:
```nix
isMeaningful = isMeaningfulName rawName;
```

- [ ] **Step 3: Update transition.nix to import isParametricWrapper**

At top of `transition.nix` let block, add:
```nix
inherit (den.lib.aspects.types) isParametricWrapper;
```

Remove inline `isParametricWrapper = v: builtins.isAttrs v && v ? __fn && v ? __args;` at line 143.

- [ ] **Step 4: Update include.nix to import shared predicates**

At top of `include.nix` let block, add:
```nix
inherit (den.lib.aspects.types) isSubmoduleFn isMeaningfulName;
```

Replace all 3 inline `canTake.upTo { lib = true; config = true; options = true; }` occurrences (lines 49, 77) with `isSubmoduleFn`.

Replace inline `isMeaningfulName` definition at line 232-233 with the imported one.

- [ ] **Step 5: Run verification**

Run: `nix develop -c just test`
Expected: 462/462 pass

---

### Task 2: Extract normalizeRoot helper

**Goal:** Deduplicate root normalization logic shared between default.nix and has-aspect.nix

**Blocked by:** Task 1 (uses `isSubmoduleFn` from types.nix)

**Files:**
- Modify: `nix/lib/aspects/default.nix:15-60` — extract to shared helper, call it
- Modify: `nix/lib/aspects/has-aspect.nix:21-46` — import and use shared helper

**Acceptance Criteria:**
- [ ] Root normalization logic exists in exactly one place
- [ ] Both `fxResolveTree` and `collectPathSet` use the shared helper
- [ ] All 462 tests pass

**Verify:** `nix develop -c just test` -> 462/462 pass

**Important:** The two normalizations currently diverge: `default.nix` handles bare module functions via `aspectType.merge`, while `has-aspect.nix` wraps all raw functions uniformly as `{ __fn, __args }`. The shared `normalizeRoot` must use `default.nix`'s behavior (module fn detection) since it's the correct handling. This changes `collectPathSet`'s normalization for bare module functions — verify carefully.

**Steps:**

- [ ] **Step 1: Extract normalizeRoot into default.nix**

In `default.nix`, extract the normalization logic from `fxResolveTree` into a standalone function. Uses `isSubmoduleFn` from Task 1:

```nix
# Normalize a root value (bare fn, functor attrset, module fn) into
# an aspect-shaped attrset suitable for the fx pipeline.
normalizeRoot =
  resolved:
  let
    isBareFn = lib.isFunction resolved && !builtins.isAttrs resolved;
    isFunctor =
      !isBareFn
      && builtins.isAttrs resolved
      && resolved ? __functor
      && builtins.isFunction (resolved.__functor resolved);
    functorArgs = if isFunctor then builtins.functionArgs (resolved.__functor resolved) else { };
    needsWrap = isFunctor && functorArgs != { };
    bareFnArgs = if isBareFn then lib.functionArgs resolved else { };
    isModuleFn = isBareFn && den.lib.aspects.types.isSubmoduleFn resolved;
  in
  if isModuleFn then
    den.lib.aspects.types.aspectType.merge
      [ "<bare-module>" ]
      [{ file = "<bare-module>"; value = resolved; }]
  else if isBareFn then
    { __fn = resolved; __args = bareFnArgs; name = "<bare-fn>"; meta = { }; }
  else if needsWrap then
    {
      __fn = resolved.__functor resolved;
      __args = functorArgs;
      name = resolved.name or "<function body>";
      meta = resolved.meta or { };
      includes = resolved.includes or [ ];
    }
    // lib.optionalAttrs (resolved ? __scopeHandlers) { inherit (resolved) __scopeHandlers; }
  else
    resolved;
```

Simplify `fxResolveTree` to use it:
```nix
fxResolveTree =
  class: resolved:
  let
    wrapped = normalizeRoot resolved;
    ctx = resolved.__ctx or { };
  in
  fx.pipeline.fxResolve { inherit class ctx; self = wrapped; };
```

- [ ] **Step 2: Update has-aspect.nix to use normalizeRoot**

Replace the inline normalization in `collectPathSet`:
```nix
collectPathSet =
  { tree, class }:
  let
    normalized = den.lib.aspects.normalizeRoot tree;
    result = den.lib.aspects.fx.pipeline.fxFullResolve {
      inherit class;
      ctx = normalized.__ctx or { };
      self = normalized;
    };
  in
  result.state.pathSet or { };
```

- [ ] **Step 3: Export normalizeRoot from default.nix**

Add `inherit normalizeRoot;` to the export attrset.

- [ ] **Step 4: Run verification**

Run: `nix develop -c just test`
Expected: 462/462 pass

---

### Task 3: Efficiency fixes

**Goal:** Fix 4 efficiency issues in hot-path pipeline code

**Files:**
- Modify: `nix/lib/aspects/fx/aspect.nix:11-26,255`
- Modify: `nix/lib/aspects/fx/handlers/tree.nix:78-88,220-234`
- Modify: `nix/lib/aspects/fx/identity.nix:54`

**Acceptance Criteria:**
- [ ] `structuralKeys` uses attrset lookup instead of `builtins.elem`
- [ ] `drainDeferredHandler` uses `lib.partition` instead of double filter
- [ ] `prefixEntries` short-circuits on empty registry
- [ ] `paths` accumulation avoids O(n^2) append
- [ ] All 462 tests pass

**Verify:** `nix develop -c just test` -> 462/462 pass

**Steps:**

- [ ] **Step 1: Convert structuralKeys to attrset in aspect.nix**

Replace:
```nix
structuralKeys = [ "name" "description" ... ];
```
With:
```nix
structuralKeysSet = lib.genAttrs [
  "name" "description" "meta" "includes" "provides" "into"
  "__fn" "__args" "__functor" "__ctx" "__scopeHandlers" "__ctxId"
  "__parametricResolved" "_module"
] (_: true);
```

Replace line 255:
```nix
classKeys = builtins.filter (k: !(builtins.elem k structuralKeys)) (builtins.attrNames aspect);
```
With:
```nix
classKeys = builtins.filter (k: !(structuralKeysSet ? ${k})) (builtins.attrNames aspect);
```

- [ ] **Step 2: Add empty registry guard in tree.nix**

In `check-constraint` handler, wrap `prefixEntries` computation:
```nix
prefixEntries =
  if registry == { } then
    [ ]
  else
    let
      parts = lib.splitString "/" identity;
      prefixes = lib.genList (i: lib.concatStringsSep "/" (lib.take (i + 1) parts)) (
        builtins.length parts - 1
      );
      getEntries = p: registry.${p} or [ ];
    in
    if builtins.length parts > 1 then builtins.concatMap getEntries prefixes else [ ];
```

- [ ] **Step 3: Use lib.partition in drainDeferredHandler**

Replace double filter:
```nix
satisfiable = builtins.filter (d: builtins.all (k: builtins.hasAttr k ctx) d.requiredArgs) deferred;
remaining = builtins.filter (d: !(builtins.all (k: builtins.hasAttr k ctx) d.requiredArgs)) deferred;
```
With:
```nix
partitioned = lib.partition (d: builtins.all (k: builtins.hasAttr k ctx) d.requiredArgs) deferred;
satisfiable = partitioned.right;
remaining = partitioned.wrong;
```

Also add short-circuit:
```nix
if deferred == [ ] then
  { resume = []; inherit state; }
else
  let ... in { resume = satisfiable; state = state // { deferredIncludes = _: remaining; }; }
```

- [ ] **Step 4: Remove dead `paths` list from identity.nix**

The `paths` field uses `(state.paths or []) ++ (lib.optional ...)` which is O(n^2). The `pathSet` attrset is the actual consumer (used by `get-path-set` handler and `collectPathSet`). Grep for `state.paths` to confirm `paths` is write-only — it is never read outside the accumulation. Remove the `paths` accumulation from `collectPathsHandler` and `defaultState` in `pipeline.nix`:

In `identity.nix`, remove from `collectPathsHandler`:
```nix
# Remove this line:
paths = (state.paths or [ ]) ++ (lib.optional (!isExcluded) path);
```

In `pipeline.nix`, remove from `defaultState`:
```nix
# Remove this line:
paths = [ ];
```

- [ ] **Step 5: Run verification**

Run: `nix develop -c just test`
Expected: 462/462 pass

---

### Task 4: Decompose forward.nix (190-line forwardItem)

**Goal:** Split the monolithic forwardItem into focused helpers for each code path

**Files:**
- Modify: `nix/lib/forward.nix`

**Acceptance Criteria:**
- [ ] `forwardItem` dispatches to 3 named helpers (each <40 lines)
- [ ] `forwardEach = forwardEach;` replaced with `inherit forwardEach;`
- [ ] All 462 tests pass

**Verify:** `nix develop -c just test` -> 462/462 pass

**Steps:**

- [ ] **Step 1: Identify shared bindings**

Keep in `forwardItem`:
- `fromClass`, `intoClass`, `intoPath`, `mapModule` (line 13-16)
- `rawAsp`, `asp`, `sourceModule` (lines 22-41)
- `needsAdapter`, `needsTopLevelAdapter` (lines 195-196)
- `freeformMod` (lines 76-78)

These are shared across all 3 paths.

- [ ] **Step 2: Extract mkDirectForward**

Extract `forward` (lines 43-74) as a top-level function taking `{ intoClass, evalConfig, sourceModule, freeformMod }`:

```nix
mkDirectForward =
  { intoClass, evalConfig, sourceModule, freeformMod }:
  path:
  if evalConfig then
    let
      evaluated = lib.evalModules { modules = [ freeformMod sourceModule ]; };
    in
    { ${intoClass} = lib.setAttrByPath path (builtins.removeAttrs evaluated.config [ "_module" ]); }
  else
    let
      value = lib.setAttrByPath path (_: { imports = [ sourceModule ]; });
    in
    { ${intoClass} = value; meta.contextDependent = true; };
```

- [ ] **Step 3: Extract mkAdapterForward**

Extract adapter logic (lines 80-145) as a top-level function.

- [ ] **Step 4: Extract mkTopLevelAdapter**

Extract top-level adapter logic (lines 180-192) as a top-level function.

- [ ] **Step 5: Simplify forwardItem dispatch**

```nix
forwardItem = { ... }@fwd:
  let
    # ... shared bindings ...
  in
  if needsTopLevelAdapter then
    mkTopLevelAdapter { ... }
  else if needsAdapter then
    mkAdapterForward { ... }
  else
    mkDirectForward { ... } intoPath;
```

- [ ] **Step 6: Fix inherit style**

Change `forwardEach = forwardEach;` to `inherit forwardEach;`.

- [ ] **Step 7: Run verification**

Run: `nix develop -c just test`
Expected: 462/462 pass

---

### Task 5: Decompose transition.nix (143-line resolveTransition)

**Goal:** Extract emitCrossProvider and fan-out sub-pipeline as top-level helpers

**Files:**
- Modify: `nix/lib/aspects/fx/handlers/transition.nix:129-272`

**Acceptance Criteria:**
- [ ] `emitCrossProvider` is a top-level function (~45 lines)
- [ ] Fan-out sub-pipeline logic is a named helper (~25 lines)
- [ ] `resolveTransition` reduced to ~70 lines (orchestration only)
- [ ] All 462 tests pass

**Verify:** `nix develop -c just test` -> 462/462 pass

**Steps:**

- [ ] **Step 1: Extract emitCrossProvider as top-level function**

Move lines 144-190 out of `resolveTransition` into a top-level `emitCrossProvider`:

```nix
emitCrossProvider =
  { crossProvider, sourceAspect, scopedCtx, scopeHandlers, ctxId }:
  prevResults:
  if crossProvider == null then
    fx.pure prevResults
  else
    let
      wrapped = ... # existing wrapping logic
    in
    fx.bind (aspectToEffect wrapped) (crossResolved: fx.pure (prevResults ++ [ crossResolved ]));
```

- [ ] **Step 2: Extract resolveFanOut as top-level function**

Move lines 233-255 into:

```nix
resolveFanOut =
  { targetClass, effectiveTarget, scopedCtx, scopeHandlers, ctxNames }:
  innerResults:
  let
    tagged = effectiveTarget // { __scopeHandlers = scopeHandlers; __ctxId = ctxNames; };
    subResult = den.lib.aspects.fx.pipeline.fxFullResolve {
      class = targetClass;
      self = tagged;
      ctx = scopedCtx;
    };
    subImports = subResult.state.imports null;
    mergeImports = fx.effects.state.modify (st: st // {
      imports = x: (st.imports x) ++ subImports;
    });
  in
  fx.bind mergeImports (_: fx.pure innerResults);
```

- [ ] **Step 3: Simplify resolveTransition to orchestration**

Use the extracted helpers in `resolveTransition`, reducing it to control flow only.

- [ ] **Step 4: Run verification**

Run: `nix develop -c just test`
Expected: 462/462 pass

---

### Task 6: Decompose aspect.nix (emitSelfProvide + aspectToEffect)

**Goal:** Break down the two largest functions in aspect.nix into focused helpers. Remove dead code.

**Files:**
- Modify: `nix/lib/aspects/fx/aspect.nix`

**Acceptance Criteria:**
- [ ] `emitSelfProvide` reduced to ~30 lines (dispatch to helpers)
- [ ] `aspectToEffect` reduced to ~40 lines
- [ ] `forwardWrap = child: child;` removed
- [ ] All 462 tests pass

**Verify:** `nix develop -c just test` -> 462/462 pass

**Steps:**

- [ ] **Step 1: Extract mkPositionalInclude from emitSelfProvide**

Extract lines 165-186 into:
```nix
mkPositionalInclude =
  { innerFn, ctx, scopeHandlers, aspect, providerMeta }:
  let
    resolved = innerFn ctx;
    resolvedArgs = if lib.isFunction resolved then lib.functionArgs resolved else { };
  in
  if lib.isFunction resolved && !builtins.isAttrs resolved then
    { name = aspect.name or "<anon>"; meta = providerMeta; __fn = resolved; __args = resolvedArgs; }
    // lib.optionalAttrs (scopeHandlers != null) { __parentScopeHandlers = scopeHandlers; }
    // lib.optionalAttrs (aspect ? __ctxId) { __parentCtxId = aspect.__ctxId; }
  else
    (if builtins.isAttrs resolved then resolved else { })
    // {
      name = aspect.name or "<anon>"; meta = providerMeta;
      includes = (if builtins.isAttrs resolved then resolved.includes or [ ] else [ ]);
    }
    // lib.optionalAttrs (aspect ? __ctxId) { __ctxId = aspect.__ctxId; };
```

- [ ] **Step 2: Extract mkNamedInclude from emitSelfProvide**

Extract lines 188-205 into:
```nix
mkNamedInclude =
  { innerFn, providerVal, isParametricWrapper', scopeHandlers, aspect, providerMeta, providerArgs }:
  {
    name = aspect.name or "<anon>";
    meta = providerMeta // (
      if isParametricWrapper' then
        builtins.removeAttrs (providerVal.meta or { }) [ "provider" "selfProvide" ]
      else { }
    );
    __fn = if lib.isFunction innerFn then innerFn else _: providerVal;
    __args = providerArgs;
  }
  // lib.optionalAttrs (scopeHandlers != null) { __parentScopeHandlers = scopeHandlers; }
  // lib.optionalAttrs (aspect ? __ctxId) { __parentCtxId = aspect.__ctxId; };
```

- [ ] **Step 3: Extract resolveParametric from aspectToEffect**

Extract lines 285-355 into a helper that handles the parametric branch:
```nix
resolveParametric =
  aspect:
  let
    userArgs = aspect.__args;
    scopeHandlers = aspect.__scopeHandlers or null;
    scopeFn = if scopeHandlers != null then fx.effects.scope.provide scopeHandlers else null;
    rawFn = aspect.__fn;
    fn = if (aspect.meta.exactMatch or false) && scopeHandlers != null
      then args: rawFn (args // { __scopeKeys = builtins.attrNames scopeHandlers; })
      else rawFn;
    resolveFn = if scopeFn != null then scopeFn (fx.bind.fn userArgs fn) else fx.bind.fn userArgs fn;
  in
  fx.bind resolveFn (resolved:
    let
      base = { ... };  # existing base construction
      next = ...;       # existing next computation (without forwardWrap)
      tagged = ...;     # existing tagging
    in
    aspectToEffect tagged
  );
```

- [ ] **Step 4: Remove forwardWrap identity function**

Remove `forwardWrap = child: child;` (line 320). Replace `forwardWrap (base // ...)` with just `base // ...` on line 340.

- [ ] **Step 5: Run verification**

Run: `nix develop -c just test`
Expected: 462/462 pass

---

### Task 7: Decompose include.nix wrapChild + types.nix providerType.merge

**Goal:** Split two oversized functions into focused branches

**Files:**
- Modify: `nix/lib/aspects/fx/handlers/include.nix:34-94`
- Modify: `nix/lib/aspects/types.nix:107-187`

**Acceptance Criteria:**
- [ ] `wrapChild` reduced to ~15 lines (dispatch)
- [ ] `providerType.merge` reduced to ~20 lines (dispatch)
- [ ] All 462 tests pass

**Verify:** `nix develop -c just test` -> 462/462 pass

**Steps:**

- [ ] **Step 1: Extract wrapFunctorChild from include.nix**

Extract lines 43-73 (attrset-functor branch of wrapChild):
```nix
wrapFunctorChild =
  child:
  let
    innerFn = child.__functor child;
    innerArgs = if builtins.isFunction innerFn then builtins.functionArgs innerFn else { };
  in
  if isSubmoduleFn innerFn then
    normalizeModuleFn innerFn
  else
    child // {
      __fn = if child ? __args then child.__fn
        else if builtins.isFunction innerFn then innerFn
        else _: innerFn;
      __args = let explicit = child.__args or { }; in
        if explicit != { } then explicit else innerArgs;
      includes = child.includes or [ ];
    };
```

- [ ] **Step 2: Extract wrapBareFn from include.nix**

Extract lines 74-91 (bare function branch):
```nix
wrapBareFn =
  child:
  let
    args = lib.functionArgs child;
  in
  if isSubmoduleFn child then
    normalizeModuleFn child
  else
    { name = child.name or "<anon>"; meta = child.meta or { }; __fn = child; __args = args; };
```

- [ ] **Step 3: Simplify wrapChild to dispatch**

```nix
wrapChild =
  child:
  if lib.isFunction child then
    if builtins.isAttrs child && child ? name && child ? includes && builtins.isList child.includes then
      child  # already-merged aspect
    else if builtins.isAttrs child then
      wrapFunctorChild child
    else
      wrapBareFn child
  else
    child;
```

- [ ] **Step 4: Extract merge helpers in types.nix**

Extract 3 helpers from `providerType.merge`:

```nix
mergeParametrics = loc: defs:
  let
    wrapper = (lib.last (builtins.filter (d: isParametricWrapper d.value) defs)).value;
    nameFromLoc = lib.last loc;
  in
  wrapper // lib.optionalAttrs (!(wrapper ? name) || wrapper.name == "<anon>") { name = nameFromLoc; };

mergeMixed = at: loc: defs:
  at.merge loc (map (d:
    if lib.isFunction d.value && !isSubmoduleFn d.value then
      d // { value = { includes = [ d.value ]; }; }
    else d
  ) defs);

mergeFunctions = at: cnf: loc: defs:
  let
    subFns = builtins.filter (d: isSubmoduleFn d.value) defs;
    paramFns = builtins.filter (d: !isSubmoduleFn d.value) defs;
  in
  if subFns != [ ] then at.merge loc subFns
  else
    let fn = (lib.last paramFns).value; in
    if builtins.isAttrs fn then fn
    else
      let args = lib.functionArgs fn; nameFromLoc = lib.last loc; in
      {
        name = nameFromLoc;
        meta = { provider = cnf.providerPrefix or [ ]; };
        __fn = fn; __args = args;
        __functor = self: self.__fn;
      };
```

- [ ] **Step 5: Simplify providerType.merge to dispatch**

```nix
merge = loc: defs:
  let
    parametrics = builtins.filter (d: isParametricWrapper d.value) defs;
  in
  if parametrics != [ ] then mergeParametrics loc defs
  else
    let
      nonParametrics = builtins.filter (d: !isParametricWrapper d.value) defs;
      hasFns = builtins.any (d: lib.isFunction d.value) nonParametrics;
      hasNonFns = builtins.any (d: !lib.isFunction d.value) nonParametrics;
    in
    if hasFns && hasNonFns then mergeMixed at loc nonParametrics
    else if hasFns then mergeFunctions at cnf loc nonParametrics
    else at.merge loc nonParametrics;
```

- [ ] **Step 6: Run verification**

Run: `nix develop -c just test`
Expected: 462/462 pass

---

### Task 8: Legacy cleanup (batteries WSL)

**Goal:** Align WSL policy with existing mkDetectHost pattern

**Files:**
- Modify: `modules/policies/batteries.nix:99-110`

**Note:** Deprecation warnings in `take.nix` and `perHost-perUser.nix` are intentionally kept — these are compat shims for downstream users.

**Acceptance Criteria:**
- [ ] WSL policy uses consistent pattern with other policies
- [ ] All 462 tests pass

**Verify:** `nix develop -c just test` -> 462/462 pass

**Steps:**

- [ ] **Step 1: Evaluate WSL refactoring feasibility**

The current WSL resolve checks `(ctx.host.wsl or { }).enable or false` — a config flag check. `mkDetectHost` checks `host-has-user-with-class host className` — a user class membership check. These are semantically different: a host can have WSL enabled without any user having the "wsl" class. WSL activation is host-level config, not user-class-driven.

If WSL is genuinely host-config-driven (no "wsl" user class exists), the inline pattern is correct and should stay. In that case, add a comment explaining why it doesn't use `mkDetectHost`:

```nix
# WSL activation is host-config-driven (wsl.enable), not user-class-driven,
# so it doesn't use mkDetectHost which requires matching user classes.
host-to-wsl-host = {
  from = "host";
  to = "wsl-host";
  resolve =
    ctx:
    if !(ctx ? host) || !(builtins.isAttrs ctx.host) then
      [ ]
    else
      lib.optional (ctx.host.class or "" == "nixos" && (ctx.host.wsl or { }).enable or false) {
        inherit (ctx) host;
      };
};
```

- [ ] **Step 2: Run verification**

Run: `nix develop -c just test`
Expected: 462/462 pass
