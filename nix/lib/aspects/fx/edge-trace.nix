# edge-trace.nix — read-only renderer of the current pipeline's delivery
# decisions as a normalized, stably-sorted edge list. This is the migration
# oracle for the delivery-edge unification port (spec
# 2026-06-12-delivery-edge-unification-design.md §3a): every Phase-2 mechanism
# port is gated by diffing its constructor's edges against the edges this
# extractor renders from the SAME end-state.
#
# v0 captures the clean edges exactly (default folds, simple routes, provides,
# spawns, instantiates). Path-dependent decisions (route suppression,
# findHostScopeId root selection, complex-forward source choice, @system
# requalification) are recorded as ANNOTATIONS (spec §3a, approximate-then-
# converge) rather than independently re-derived — re-deriving them would mean
# re-implementing the very logic the port deletes. Annotation fidelity converges
# to exact edge fields constructor-by-constructor in Phase 2.
#
# Edge record:  { source; target; path; mode; annotations; }
#   S (source)  — collected(scopeName, class) | rewalk(aspect, bindings, class)
#                 | synthesize(forwardId, fromClass, intoClass)
#   T (target)  — { root = scopeName; class; }  (instantiation root)
#                 | { output = attrpath; }      (flake-output)
#   P (path)    — attrpath; [] = merge at root
#   M (mode)    — "merge" | "nest" | "nest-verbatim"
#
# Trace normalization (spec §8): sort key (T, P, S, M); entity scopes named by
# id_hash (parent-blind identity), non-entity scopes by their mkScopeId string;
# rewalk/synthesize edges record the identity triple, NOT resolved content.
{ lib, den }:
let
  # Reuse the ACTUAL route suppression logic (not a reimplementation): the
  # point of the extractor is to render the decisions the current code makes.
  route = import ./route { inherit lib den; };
  inherit (route) dedupRoutes findChildScopeKeys;
  # Share the ONE subtree walk with production (resolve.nix / route / spawn) so
  # the oracle and the real pipeline can never diverge on subtree membership.
  inherit (import ./scope-walk.nix { inherit lib; }) subtreeScopes;

  # --- scope naming -------------------------------------------------------

  # Entity kind for a scope, if any. scopeEntityKind covers scopes created by
  # `resolve.to`, but NOT the pipeline root (it is seeded from ctx, never
  # `resolve.to`-created). For the root (and any ctx-seeded entity scope), scan
  # the scope's own ctx for a kind-keyed record carrying an id_hash.
  entityKindOf =
    { scopeEntityKind, scopeContexts }:
    sid:
    let
      viaKind = scopeEntityKind.${sid} or null;
      ctx = scopeContexts.${sid} or { };
      # A ctx key whose value is an entity record (has id_hash). Sorted for
      # determinism; first wins (a scope carries one own-entity record).
      ctxKinds = lib.filter (k: builtins.isAttrs (ctx.${k} or null) && (ctx.${k} ? id_hash)) (
        lib.sort (a: b: a < b) (builtins.attrNames ctx)
      );
    in
    if viaKind != null then
      viaKind
    else if ctxKinds != [ ] then
      builtins.head ctxKinds
    else
      null;

  # id_hash of the own-entity record at a scope, if the scope is an entity scope.
  idHashOf =
    args@{ scopeEntityKind, scopeContexts }:
    sid:
    let
      kind = entityKindOf args sid;
      erec = if kind == null then null else (scopeContexts.${sid} or { }).${kind} or null;
    in
    if erec == null then null else erec.id_hash or null;

  # Stable scope NAME for S/T. Entity scopes → "<kind>:<id_hash>" (parent-blind
  # identity, stable across re-keying and same-name siblings collapse by design,
  # spec §8). Non-entity scopes (system=…, root "") → the mkScopeId string.
  scopeName =
    args@{ scopeEntityKind, scopeContexts }:
    sid:
    let
      kind = entityKindOf args sid;
      idHash = idHashOf args sid;
    in
    if kind != null && idHash != null then
      "${kind}:${idHash}"
    else
      (if sid == "" then "<root>" else sid);

  # --- subtree walk (isolation-aware, matching extractSubtreeModules) ------

  # Scope IDs in root's subtree: root always included; isolation gates crossing
  # INTO a descendant (resolve.nix:extractSubtreeModules / collectFromSubtree).
  subtreeScopesOf =
    {
      scopeParent,
      scopeIsolated,
      allScopeIds,
    }:
    root:
    subtreeScopes {
      inherit scopeParent allScopeIds root;
      isolated = scopeIsolated;
    };

  # --- edge record + sort -------------------------------------------------

  mkEdge =
    {
      source,
      target,
      path ? [ ],
      mode,
      annotations ? { },
    }:
    {
      inherit
        source
        target
        path
        mode
        annotations
        ;
    };

  # Canonical string keys for stable sort (spec §8: T, P, S, M).
  targetKey =
    t: if t ? output then "out:${lib.concatStringsSep "." t.output}" else "root:${t.root}/${t.class}";
  pathKey = p: lib.concatStringsSep "/" p;
  sourceKey =
    s:
    if s ? collected then
      "collected:${s.collected.scope}/${s.collected.class}"
    else if s ? rewalk then
      "rewalk:${s.rewalk.aspect}/${lib.concatStringsSep "+" s.rewalk.bindings}/${s.rewalk.class}"
    else if s ? synthesize then
      "synthesize:${s.synthesize.forwardId}/${s.synthesize.fromClass}>${s.synthesize.intoClass}"
    else
      "empty";
  edgeSortKey =
    e:
    lib.concatStringsSep " | " [
      (targetKey e.target)
      (pathKey e.path)
      (sourceKey e.source)
      e.mode
    ];

  sortEdges = edges: lib.sort (a: b: edgeSortKey a < edgeSortKey b) edges;

  # --- S/T constructors ---------------------------------------------------

  collected = scope: class: { collected = { inherit scope class; }; };
  rewalk = aspect: bindings: class: { rewalk = { inherit aspect bindings class; }; };
  synthesize = forwardId: fromClass: intoClass: {
    synthesize = { inherit forwardId fromClass intoClass; };
  };
  rootTarget = root: class: { inherit root class; };
  outputTarget = output: { inherit output; };
in
{
  # extractEdgeTrace: pipeline end-state → stably-sorted normalized edge list.
  extractEdgeTrace =
    {
      scopeContexts,
      scopeParent,
      scopeIsolated,
      scopeEntityKind,
      scopedClassImports,
      scopedRoutes,
      scopedProvides,
      scopedSpawns,
      scopedInstantiates,
      rootScopeId,
      dedupProvides,
    }:
    let
      nameArgs = { inherit scopeEntityKind scopeContexts; };
      name = scopeName nameArgs;
      kindOf = entityKindOf nameArgs;

      allScopeIds = builtins.attrNames scopeContexts;

      # Entity-root scopes: the pipeline root + every isolated scope (an isolated
      # entity is its OWN collection root — isolation = edge-absence into its
      # parent, spec §2). Each is a default-fold T.
      entityRootScopes = lib.unique (
        [ rootScopeId ] ++ builtins.filter (sid: scopeIsolated.${sid} or false) allScopeIds
      );

      # ===== default fold edges ==========================================
      # One per entity-root scope per class with content:
      #   collected(subtree minus isolated, class) → (root, class), P=[], M=merge.
      # Source content is collected from the isolation-aware subtree; the edge
      # records the source as the subtree's ROOT scope name + class (the
      # collection is keyed by root, not enumerated per-scope — spec §8 records
      # the collected(scope,class) identity, not content).
      defaultFoldEdges = builtins.concatLists (
        map (
          rootSid:
          let
            subtree = subtreeScopesOf {
              inherit scopeParent scopeIsolated allScopeIds;
            } rootSid;
            # Classes with any content anywhere in the subtree.
            classesWithContent = lib.unique (
              builtins.concatLists (map (sid: builtins.attrNames (scopedClassImports.${sid} or { })) subtree)
            );
            hasContent = cls: builtins.any (sid: (scopedClassImports.${sid} or { }) ? ${cls}) subtree;
            # The normalized names of every scope this fold collects from — the
            # isolation-aware subtree (an isolated descendant is its OWN root, so
            # it is ABSENT here). Surfaced as an annotation so the isolation-as-
            # edge-absence corollary can assert with teeth: an isolated child's
            # scope name must NOT appear in its parent fold's collectedScopes.
            collectedScopes = lib.sort (a: b: a < b) (lib.unique (map name subtree));
          in
          map (
            cls:
            mkEdge {
              source = collected (name rootSid) cls;
              target = rootTarget (name rootSid) cls;
              path = [ ];
              mode = "merge";
              annotations = {
                inherit collectedScopes;
              };
            }
          ) (builtins.filter hasContent classesWithContent)
        ) entityRootScopes
      );

      # ===== provides edges (two-edge decomposition, §B Decision 1) ======
      # A provides spec → a nest edge into the SOURCE scope's bucket
      # (setAttrByPath path module). The merge half is the default fold edge
      # already emitted above (the perScope append is subtree-collectible) — we
      # render only the nest edge, annotated providesPolicyName, with a note that
      # the merge half is the default fold. Dedup key = (policyName, class, path)
      # — the SAME composite key applyProvides/dedupProvides uses (NOT scope-
      # keyed): two provides from one policy into one class+path collapse to one
      # edge regardless of registering scope.
      allProvides = builtins.concatLists (lib.attrValues scopedProvides);
      dedupedProvides = dedupProvides allProvides;
      providesEdges = map (
        spec:
        let
          path = spec.path or [ ];
          sid = spec.sourceScopeId;
        in
        mkEdge {
          # Source is the provided module placed at P (nest construction);
          # rendered as a collected source into the source scope's class bucket.
          source = collected (name sid) spec.class;
          target = rootTarget (name sid) spec.class;
          inherit path;
          # P=[] degenerates to a plain merge contribution (no nesting); P!=[]
          # is the setAttrByPath nest construction.
          mode = if path == [ ] then "merge" else "nest";
          annotations = {
            providesPolicyName = spec.__providePolicyName or null;
            # The merge half (delivery to the entity root) is the default fold
            # edge above; this nest edge only constructs the placed module.
            mergeHalf = "default-fold";
          };
        }
      ) dedupedProvides;

      # ===== route edges =================================================
      # From scopedRoutes specs (post the ACTUAL dedupRoutes — reused, not
      # reimplemented). Simple routes and complex (synthesize) forwards.
      rawRoutes = builtins.concatLists (lib.attrValues scopedRoutes);
      # The suppression decisions: which adapterKey@scope routes dedupRoutes
      # keeps, and which child keys shadow root-scope adapter routes. Reuse the
      # real functions over the SAME rootScopeId the pipeline used.
      keptRoutes = dedupRoutes rootScopeId rawRoutes;
      childKeys = findChildScopeKeys rootScopeId rawRoutes;
      # Per-position suppression verdicts. A rawRoute is suppressed iff
      # dedupRoutes (the ACTUAL logic, reused — not reimplemented) dropped it,
      # i.e. it is not the kept instance of its identity. keptRoutes preserves
      # original order and keeps the FIRST instance per identity, so a verdict is
      # derived by consuming keptRoutes positionally as rawRoutes are walked: the
      # head of keptRoutes is the kept route until matched, then advances.
      # `byChild` (redundant-root shadow, §B rule 2) is recomputed from the same
      # findChildScopeKeys output dedupRoutes consumes.
      suppressVerdicts =
        let
          go =
            kept: routes:
            if routes == [ ] then
              [ ]
            else
              let
                r = builtins.head routes;
                rest = builtins.tail routes;
                # Identity assumption: dedupRoutes preserves original order and
                # returns the SAME route records (by reference) it kept, so the
                # head-of-kept structural `==` here is really reference identity —
                # two distinct rawRoutes are never structurally equal in practice
                # (each carries a distinct sourceScopeId/path). If dedupRoutes ever
                # rebuilds records, switch this to a stable adapterKey@scope match.
                isKept = kept != [ ] && builtins.head kept == r;
                ak = r.adapterKey or null;
                # Redundant-root shadow: an adapter route AT the root scope whose
                # adapterKey also exists at a child scope (findChildScopeKeys).
                byChild = ak != null && rootScopeId != null && r.sourceScopeId == rootScopeId && childKeys ? ${ak};
                verdict = {
                  suppressed = !isKept;
                  inherit byChild;
                };
              in
              [ verdict ] ++ go (if isKept then builtins.tail kept else kept) rest;
        in
        go keptRoutes rawRoutes;

      # A forward identity triple component (§B Decision 2): adapterKey if
      # present (the dynamic-P adapter arm, cell 6), else a structural composite.
      forwardId =
        spec:
        spec.adapterKey or "${spec.fromClass}>${spec.intoClass}@${spec.sourceScopeId}/${
          lib.concatStringsSep "/" (spec.staticIntoPath or spec.path or [ ])
        }";

      routeEdge =
        verdict: spec:
        let
          sid = spec.sourceScopeId;
          isComplex = spec.__complexForward or false;
          path = spec.path or spec.staticIntoPath or [ ];
          appendToParent = spec.appendToParent or false;
          appendSid = if appendToParent then scopeParent.${sid} or sid else sid;
          adapterKey = spec.adapterKey or null;
          reinstantiate = spec.reinstantiate or false;
          # Suppression verdict for this position (path-dependent — depends on
          # the SET of routes present, §B path-dependent suppression rule).
          # Recorded as an annotation until the route port (spec §3a).
          isSuppressed = verdict.suppressed;
          suppressedByChild = verdict.byChild;

          baseAnnotations =
            lib.optionalAttrs (spec.adaptArgs or null != null) { adaptArgs = true; }
            // lib.optionalAttrs (spec.guard or null != null) { guard = true; }
            // lib.optionalAttrs (spec.collectSubtree or false) { collectSubtree = true; }
            // lib.optionalAttrs ((spec.intoClass or null) == "flake") { isFlakeRoute = true; }
            // lib.optionalAttrs ((spec.instantiate or null) != null) { instantiate = true; }
            // lib.optionalAttrs appendToParent { appendToParent = true; }
            // lib.optionalAttrs (
              # §B cell 5: ensureEntry placeholder (empty target path materialized).
              # (content-blind approx; real ensureEntry also requires empty module
              # set — converges Phase 2)
              !isComplex && (spec.intoClass or null) != "flake" && (spec.adaptArgs or null) != null && path != [ ]
            ) { ensureTargetPath = true; }
            // lib.optionalAttrs isSuppressed { suppressed = true; }
            // lib.optionalAttrs suppressedByChild { suppressedByChildKey = adapterKey; };
        in
        if isComplex then
          # Complex forward → synthesize edge. Identity triple only (no content,
          # spec §8). sourceVia is path-dependent (getCollectedSource's collected-
          # else-rewalk branch depends on the assembled perScope, which v0 does
          # not reconstruct) — recorded as the approximate annotation
          # "unresolved" per the Task-3 brief.
          mkEdge {
            source = synthesize (forwardId spec) spec.fromClass spec.intoClass;
            target = rootTarget (name appendSid) spec.intoClass;
            inherit path;
            mode = "nest";
            annotations = baseAnnotations // {
              complexForward = true;
              sourceVia = "unresolved";
            };
          }
        else
          mkEdge {
            source = collected (name sid) spec.fromClass;
            target = rootTarget (name appendSid) spec.intoClass;
            inherit path;
            # §B Decision 4: reinstantiate ⇒ nest-verbatim; P=[] ⇒ merge;
            # else nest. Adapter routes (cell 6) carry dynamic P — annotated.
            mode =
              if reinstantiate then
                "nest-verbatim"
              else if path == [ ] then
                "merge"
              else
                "nest";
            annotations =
              baseAnnotations
              // lib.optionalAttrs (adapterKey != null) {
                inherit adapterKey;
                # §B cell 6: adapter arm resolves P dynamically at evalModules
                # time via intoPathFn — P is not a static edge field.
                dynamicPath = true;
              };
          };
      routeEdges = lib.imap0 (i: spec: routeEdge (builtins.elemAt suppressVerdicts i) spec) rawRoutes;

      # ===== spawn (rewalk) edges ========================================
      # scopedSpawns: each marker lives at an OWN entity scope (ownKind); the
      # spawned class is re-walked from the PARENT scope's own entity aspect,
      # with the own entity bound under its kind → delivered to the own scope
      # root. Identity triple: (parent aspect identity, bound kinds, class).
      # Content is NOT recorded (spec §8 rewalk determinism).
      spawnEdges = builtins.concatLists (
        lib.mapAttrsToList (
          ownSid: specs:
          let
            ownKind = kindOf ownSid;
            from = scopeParent.${ownSid} or null;
            parentKind = if from == null then null else kindOf from;
            parentRec =
              if parentKind == null then null else (scopeContexts.${from} or { }).${parentKind} or null;
            ownRec = if ownKind == null then null else (scopeContexts.${ownSid} or { }).${ownKind} or null;
            # Parent aspect identity: prefer the record's id_hash, else its name.
            aspectId =
              if parentRec == null then "<unknown>" else parentRec.id_hash or parentRec.name or "<unknown>";
            defaultClasses = if ownRec == null then [ ] else ownRec.classes or [ ];
            classes = lib.unique (
              builtins.concatLists (map (s: if s.classes != null then s.classes else defaultClasses) specs)
            );
          in
          map (
            cls:
            mkEdge {
              source = rewalk aspectId [ ownKind ] cls;
              target = rootTarget (name ownSid) cls;
              path = [ ];
              mode = "merge";
              annotations = {
                spawnFrom = if from == null then null else name from;
              };
            }
          ) classes
        ) scopedSpawns
      );

      # ===== instantiate edges (flake-output T-arm) ======================
      # scopedInstantiates → flake-output edges. T = [ "flake" ] ++ intoAttr.
      # @system disambiguation: when the SAME output path is targeted by specs
      # on DIFFERENT systems, each is qualified <name>@<system>. We render the
      # disambiguation by reusing the grouping INPUTS (path + system metadata
      # only — never spec.instantiate, matching disambiguated's contract) and
      # annotate collisions (disambiguatedTo). resolvedRootVia annotation =
      # "name-infix" with the hostScopeId findHostScopeId currently returns
      # (the heuristic to dissolve in Task 11).
      allInstantiates = builtins.concatLists (lib.attrValues scopedInstantiates);
      # Spec descriptors with output, mirroring applyInstantiates:specDescriptors.
      instDescriptors = builtins.concatLists (
        map (
          spec:
          let
            hasOutput = (spec.intoAttr or [ ]) != [ ];
          in
          if !hasOutput then
            [ ]
          else
            [
              {
                path = [ "flake" ] ++ spec.intoAttr;
                system = spec.system or null;
                inherit spec;
              }
            ]
        ) allInstantiates
      );
      # Group by output path (the disambiguated grouping inputs).
      instGrouped = builtins.foldl' (
        acc: entry:
        let
          k = lib.concatStringsSep "." entry.path;
        in
        acc // { ${k} = (acc.${k} or [ ]) ++ [ entry ]; }
      ) { } instDescriptors;
      instantiateEdges = builtins.concatLists (
        lib.mapAttrsToList (
          _: entries:
          let
            systems = lib.unique (map (e: e.system or null) entries);
            isMultiSystem = builtins.length entries > 1 && builtins.length systems > 1;
          in
          map (
            entry:
            let
              spec = entry.spec;
              # findHostScopeId is a let-binding inside resolve.nix (not
              # exported); we record the resolution VIA, not the heuristic. The
              # spec carries sourceScopeId; the host scope it resolves to is a
              # child of that by name-infix. We annotate resolvedRootVia only.
              outPath =
                if isMultiSystem then
                  lib.init entry.path ++ [ "${lib.last entry.path}@${entry.system}" ]
                else
                  entry.path;
            in
            mkEdge {
              # Source content comes from the host subtree (collected); we record
              # the source as the spec's source scope + class.
              source = collected (name (spec.sourceScopeId or rootScopeId)) (spec.class or "nixos");
              target = outputTarget outPath;
              path = [ ];
              mode = "merge";
              annotations = {
                resolvedRootVia = "name-infix";
                inherit (entry) system;
              }
              // lib.optionalAttrs isMultiSystem {
                disambiguatedTo = lib.concatStringsSep "." outPath;
              };
            }
          ) entries
        ) instGrouped
      );

      allEdges = defaultFoldEdges ++ providesEdges ++ routeEdges ++ spawnEdges ++ instantiateEdges;
    in
    sortEdges allEdges;
}
