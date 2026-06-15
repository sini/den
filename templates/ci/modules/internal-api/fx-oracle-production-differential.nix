# fx-oracle-production-differential suite — the Task 18.3 differential gate.
#
# As of Task 18.2 the resolveWithPaths result carries TWO edge objects side by
# side:
#   - `edgeTrace`       — the PRODUCTION edge object. Its fold-ordered
#                         provides+routes portion is CAPTURED from the production
#                         materializeUnified folds (the top-level fold, the spawn's
#                         surfaced `.edges`, the per-host `.edges`); its default-fold
#                         + instantiate edges are constructor-built. This is
#                         drift-proof for the captured part.
#   - `legacyEdgeTrace` — the LEGACY end-state RE-DERIVATION (edge-trace.nix
#                         extractEdgeTrace), WITH its spawn `rewalk` arm (the
#                         spawn UNDERCOUNT) and the dedup-suppressed route twins.
#
# This suite diffs the two on a SPAWN topology and an INSTANTIATE topology and
# pins the load-bearing relationship:
#
#   (A) PRODUCTION ⊇ (LEGACY minus its rewalk-source edges) — every legacy edge
#       that is NOT a spawn rewalk survives (by normalized key) in the production
#       object. The rewalk edges are the ONLY legacy edges production drops; it
#       replaces them with the spawn's real surfaced edges.
#
#   (B) the production-only delta (edges in production NOT in legacy, by key) on
#       the spawn topology is NON-EMPTY and CONTAINS the spawn's surfaced route /
#       default-fold edge — the concrete homeManager fold into the user root that
#       the legacy oracle's single rewalk edge collapsed away.
#
# This is a PRODUCTION-vs-LEGACY differential (NOT production-vs-self): `oracle`
# binds `legacyEdgeTrace`, `production` binds `edgeTrace`.
#
# `just ci fx-oracle-production-differential` runs this suite.
{ denTest, lib, ... }:
let
  # Stable sort key mirroring edges/edge.nix edgeSortKey (T, P, S, M), so the two
  # edge lists are compared as normalized SETS regardless of construction order.
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
  edgeKey =
    e:
    lib.concatStringsSep " | " [
      (targetKey e.target)
      (pathKey e.path)
      (sourceKey e.source)
      e.mode
    ];

  keySet = edges: lib.genAttrs (map edgeKey edges) (_: true);
  isSubset = sub: super: lib.all (e: (keySet super) ? ${edgeKey e}) sub;

  # The fleet → hosts include policy shared by the spawn + instantiate topologies
  # (a flake-level resolve that fans out to each host with an instantiate spec).
  fleetSetup = den: lib: {
    den.policies.to-fleet = _: [
      (den.lib.policy.resolve.to "fleet" {
        fleet = {
          name = "fleet";
        };
      })
    ];
    den.policies.fleet-to-hosts =
      { fleet, ... }:
      lib.concatMap (
        system:
        lib.concatMap (
          hostName:
          let
            host = den.hosts.${system}.${hostName};
          in
          [
            (den.lib.policy.resolve.to "host" { inherit host; })
            (den.lib.policy.instantiate host)
          ]
        ) (builtins.attrNames (den.hosts.${system} or { }))
      ) (builtins.attrNames (den.hosts or { }));
    den.schema.flake.includes = [ den.policies.to-fleet ];
    den.schema.fleet.includes = [ den.policies.fleet-to-hosts ];
    den.schema.flake-system.excludes = [
      den.policies.system-to-os-outputs
      den.policies.system-to-hm-outputs
    ];
  };
in
{
  flake.tests.fx-oracle-production-differential = {

    # ===== SPAWN topology (flake-level, host-aspects battery) ============
    # A user under a host runs the host-aspects battery → a policy.spawn marker.
    # The LEGACY object renders ONE rewalk edge for it; the PRODUCTION object drops
    # the rewalk arm and surfaces the spawn's real delivered edges (its homeManager
    # default fold into the user root). We diff the two:
    #   (A) production ⊇ (legacy minus its rewalk-source edges);
    #   (B) the production-only delta is non-empty AND contains the surfaced spawn
    #       homeManager fold into the user root.
    test-spawn-production-superset-of-oracle = denTest (
      { den, lib, ... }:
      let
        r = den.lib.aspects.resolveWithPaths "flake" (den.lib.resolveEntity "flake" { });
        oracle = r.legacyEdgeTrace;
        production = r.edgeTrace;
        oracleNoRewalk = lib.filter (e: !(e.source ? rewalk)) oracle;
        # The legacy object DID carry a rewalk edge (the undercount we correct).
        oracleRewalk = lib.filter (e: e.source ? rewalk) oracle;
        # Production-only edges (the surfaced spawn's real delivered edges, which
        # the single legacy rewalk edge collapsed away).
        oracleKeys = keySet oracle;
        productionOnly = lib.filter (e: !(oracleKeys ? ${edgeKey e})) production;
        # The surfaced spawn delivers a homeManager default fold into the user
        # root — the concrete edge that replaces the legacy rewalk edge.
        surfacedSpawnHmFold = lib.any (
          e:
          e.mode == "merge"
          && e.path == [ ]
          && e.source ? collected
          && e.source.collected.class == "homeManager"
          && e.target ? root
          && lib.hasInfix "user" e.target.root
          && e.target.class == "homeManager"
        ) productionOnly;
      in
      fleetSetup den lib
      // {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.aspects.igloo.homeManager.home.sessionVariables.X = "y";
        den.aspects.tux.includes = [ den.batteries.host-aspects ];
        den.aspects.igloo.nixos.networking.hostName = "igloo";

        expr = {
          # The legacy object has a rewalk arm (the spawn undercount).
          oracleHasRewalk = oracleRewalk != [ ];
          # (A) production ⊇ (legacy minus rewalk).
          productionSupersetOfOracleMinusRewalk = isSubset oracleNoRewalk production;
          # The production object dropped the rewalk arm entirely.
          productionHasNoRewalk = lib.all (e: !(e.source ? rewalk)) production;
          # (B) production-only delta non-empty AND carries the surfaced spawn fold.
          productionDeltaNonEmpty = productionOnly != [ ];
          inherit surfacedSpawnHmFold;
        };
        expected = {
          oracleHasRewalk = true;
          productionSupersetOfOracleMinusRewalk = true;
          productionHasNoRewalk = true;
          productionDeltaNonEmpty = true;
          surfacedSpawnHmFold = true;
        };
      }
    );

    # ===== INSTANTIATE topology (flake-level fleet, no spawn) ============
    # A flake-level fleet resolve with an instantiate spec but NO spawn marker. The
    # legacy object has no rewalk arm, so the FULL legacy set survives in the
    # production object; production ADDS the per-host surfaced fold edges the
    # instantiate projection derives (host-rooted default folds the legacy top-level
    # set does not). We diff the two:
    #   (A) production ⊇ legacy (the full set — no rewalk to drop);
    #   (B) the production-only delta is non-empty AND contains a host-rooted
    #       default fold (the per-host projection's signature).
    test-instantiate-production-superset-of-oracle = denTest (
      { den, lib, ... }:
      let
        r = den.lib.aspects.resolveWithPaths "flake" (den.lib.resolveEntity "flake" { });
        oracle = r.legacyEdgeTrace;
        production = r.edgeTrace;
        oracleHasRewalk = lib.any (e: e.source ? rewalk) oracle;
        oracleKeys = keySet oracle;
        productionOnly = lib.filter (e: !(oracleKeys ? ${edgeKey e})) production;
        # A per-host default-fold edge: merge, P=[], targeting a host root's class.
        hostRootedFoldInDelta = lib.any (
          e:
          e.mode == "merge"
          && e.path == [ ]
          && e.source ? collected
          && e.target ? root
          && lib.hasInfix "host" e.target.root
        ) productionOnly;
      in
      fleetSetup den lib
      // {
        den.hosts.x86_64-linux.igloo.users = { };
        den.aspects.igloo.nixos.networking.hostName = "igloo";

        expr = {
          # No spawn → the legacy object has no rewalk edge.
          oracleHasNoRewalk = !oracleHasRewalk;
          # (A) the full legacy set survives in the production object.
          productionSupersetOfOracle = isSubset oracle production;
          # (B) production-only delta non-empty AND carries a host-rooted fold.
          productionDeltaNonEmpty = productionOnly != [ ];
          inherit hostRootedFoldInDelta;
        };
        expected = {
          oracleHasNoRewalk = true;
          productionSupersetOfOracle = true;
          productionDeltaNonEmpty = true;
          hostRootedFoldInDelta = true;
        };
      }
    );
  };
}
