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
{ lib, den, ... }:
let
  # The shared edge record, sort key, scope-naming, and S/T constructors — the
  # ONE edge definition production (edges/default.nix) and this oracle share, so
  # they can never diverge (spec §3a convergence). EXTRACTED to edges/edge.nix.
  inherit (import ./edges/edge.nix { inherit lib; })
    entityKindOf
    scopeName
    mkEdge
    sortEdges
    collected
    rewalk
    synthesize
    rootTarget
    outputTarget
    ;
  # The default-fold edge constructor — the SAME constructor production resolves
  # the per-host extraction through (edges/materialize.nix). v0's inline default-
  # fold arm is REPLACED by this import so extractor and production converge on
  # one constructor (spec §3a).
  inherit (import ./edges/default.nix { inherit lib; }) defaultFoldEdges;
  # The route edge constructor — the SAME constructor production materializes
  # simple + complex routes through (edges/route.nix applyRoutes). v0's inline
  # route arm + its own dedup/suppression re-derivation is REPLACED by this
  # import: the oracle and production now converge on ONE route constructor
  # (spec §3a). The `suppressed` annotations are now EXACT (the constructor's own
  # dedup rules), not the v0 path-dependent approximation; `sourceVia` for complex
  # forwards stays "unresolved" (the collected-else-rewalk source choice is
  # materialization-time path-dependent — see routeEdges' note).
  inherit (import ./edges/route.nix { inherit lib den; }) routeEdges;
  # The provides edge constructor — the SAME constructor production materializes
  # provides through (resolve.nix phase-2 → edges/provides.nix applyProvidesEdges).
  # v0's inline provides arm + its own dedup is REPLACED by this import: oracle and
  # production converge on ONE provides constructor (spec §3a). The two-edge
  # decomposition (nest into source bucket, merge half = default-fold) is recorded
  # by the constructor's `mergeHalf` annotation (§B Decision 1).
  inherit (import ./edges/provides.nix { inherit lib den; }) providesEdges;
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
      # The SAME constructor production routes the per-host extraction through
      # (edges/default.nix defaultFoldEdges → edges/materialize.nix). v0's inline
      # arm is gone; the oracle and production share one constructor (spec §3a).
      # classContentAt = the per-scope class buckets (only `? class` membership is
      # read for content presence).
      defaultFold = defaultFoldEdges {
        inherit
          name
          scopeParent
          scopeIsolated
          allScopeIds
          entityRootScopes
          ;
        classContentAt = scopedClassImports;
      };

      # ===== provides edges (two-edge decomposition, §B Decision 1) ======
      # Rendered by the SHARED provides constructor (edges/provides.nix
      # providesEdges) — the SAME constructor production materializes provides
      # through (resolve.nix phase-2 → applyProvidesEdges). Each spec → a nest edge
      # into the SOURCE scope's bucket; the merge half is the default-fold edge
      # (annotated mergeHalf). Dedup key = (policyName, class, path), NOT scope-
      # keyed (§B Decision 1).
      providesEdgeList = providesEdges { inherit name scopedProvides; };

      # ===== route edges =================================================
      # Rendered by the SHARED route constructor (edges/route.nix routeEdges) —
      # the SAME constructor production materializes simple routes through
      # (edges/route.nix applyRoutes → materializeRouteEdge). The oracle no longer re-derives
      # suppression: the constructor's own dedup/suppression rules are EXACT here
      # (the `suppressed`/`suppressedByChildKey` annotations are the production
      # decisions, not the v0 approximation). Complex forwards keep
      # `sourceVia = "unresolved"` (Task 9).
      rawRoutes = builtins.concatLists (lib.attrValues scopedRoutes);
      routeEdgeList = routeEdges {
        inherit
          name
          scopeParent
          rootScopeId
          rawRoutes
          ;
      };

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

      allEdges = defaultFold ++ providesEdgeList ++ routeEdgeList ++ spawnEdges ++ instantiateEdges;
    in
    sortEdges allEdges;
}
