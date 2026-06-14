# fx-unified-edges suite — the unifiedEdges(root) collector
# (nix/lib/aspects/fx/resolve.nix), the union edge set that CORRECTS the oracle's
# (edge-trace.nix) spawn UNDERCOUNT: it is the oracle's top-level mechanism set
# MINUS the single `rewalk` arm, PLUS the SURFACED spawn edges (the spawn node's
# real default-fold + provides + route edges) and the per-host / B′ instantiate
# edges.
#
# `unifiedEdges` sits beside `edgeTrace` on the resolveWithPaths result, reached
# the same way the delivery-edges suite reaches `edgeTrace`.
#
# `just ci fx-unified-edges` runs this suite.
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

  # The resolve result (carries edgeTrace + unifiedEdges side by side).
  hostResult =
    den: cls: host:
    den.lib.aspects.resolveWithPaths cls (den.lib.resolveEntity "host" { inherit host; });
in
{
  flake.tests.fx-unified-edges = {

    # ===== (1) spawn topology: unifiedEdges fixes the rewalk undercount =====
    # The host-aspects battery on a user emits a policy.spawn marker; the oracle
    # renders ONE rewalk edge for it, but the spawn actually delivers a full edge
    # set (its homeManager default fold + the re-applied mergedSpawnRoutes route
    # edges). unifiedEdges drops the oracle's rewalk arm and adds the surfaced
    # spawn edges, so:
    #   - unifiedEdges is a superset of (edgeTrace MINUS its rewalk edges);
    #   - unifiedEdges contains at least one edge the oracle OMITTED (the surfaced
    #     spawn delivered a route/default-fold edge the rewalk arm collapsed away).
    test-spawn-superset-of-oracle-minus-rewalk = denTest (
      { den, lib, ... }:
      let
        # FLAKE-level resolve: the drain-fold spawn (mkDrained) fires only when
        # the spawn's parent scope is a resolve.to-created entity scope (so it is
        # in scopeEntityKind). At HOST level the host is the ctx-seeded root, not
        # in scopeEntityKind, so the drain-fold spawn arm is a no-op there — the
        # surfaced spawn edges only exist at flake level.
        r = den.lib.aspects.resolveWithPaths "flake" (den.lib.resolveEntity "flake" { });
        oracle = r.edgeTrace;
        unified = r.unifiedEdges;
        oracleNoRewalk = lib.filter (e: !(e.source ? rewalk)) oracle;
        # Edges the unified set has that the oracle did NOT (the surfaced spawn's
        # real delivered edges, which the single rewalk edge collapsed away).
        oracleKeys = keySet oracle;
        novelInUnified = lib.filter (e: !(oracleKeys ? ${edgeKey e})) unified;
        # The oracle DID carry a rewalk edge (the undercount we are correcting).
        oracleRewalk = lib.filter (e: e.source ? rewalk) oracle;
      in
      {
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
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.aspects.igloo.homeManager.home.sessionVariables.X = "y";
        den.aspects.tux.includes = [ den.batteries.host-aspects ];
        den.aspects.igloo.nixos.networking.hostName = "igloo";

        expr = {
          oracleHasRewalk = oracleRewalk != [ ];
          unifiedHasNoRewalk = lib.all (e: !(e.source ? rewalk)) unified;
          unifiedSupersetOfOracleMinusRewalk = isSubset oracleNoRewalk unified;
          unifiedHasNovelEdges = novelInUnified != [ ];
          # The surfaced spawn delivers a homeManager default fold into the user
          # root — a concrete edge the oracle's single rewalk edge collapsed away.
          unifiedHasUserHmFold = lib.any (
            e:
            e.mode == "merge"
            && e.path == [ ]
            && e.source ? collected
            && e.source.collected.class == "homeManager"
            && e.target ? root
            && lib.hasInfix "user" e.target.root
            && e.target.class == "homeManager"
          ) unified;
        };
        expected = {
          oracleHasRewalk = true;
          unifiedHasNoRewalk = true;
          unifiedSupersetOfOracleMinusRewalk = true;
          unifiedHasNovelEdges = true;
          unifiedHasUserHmFold = true;
        };
      }
    );

    # ===== (2) plain host+user (no spawn): unifiedEdges ⊇ oracle =============
    # With NO spawn marker the oracle has no rewalk arm, so unifiedEdges contains
    # the SAME top-level mechanism edges (default folds + os routes + the user
    # forward) AND augments them with the per-host instantiate edges. We assert the
    # full oracle set is a subset of unifiedEdges (nothing top-level dropped).
    test-plain-superset-of-oracle = denTest (
      { den, lib, ... }:
      let
        r = hostResult den "nixos" den.hosts.x86_64-linux.igloo;
        oracle = r.edgeTrace;
        unified = r.unifiedEdges;
        oracleHasRewalk = lib.any (e: e.source ? rewalk) oracle;
      in
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.aspects.igloo.nixos.networking.hostName = "igloo";

        expr = {
          # No spawn in this topology → oracle has no rewalk edge.
          oracleHasNoRewalk = !oracleHasRewalk;
          # The whole oracle set survives in unifiedEdges.
          unifiedSupersetOfOracle = isSubset oracle unified;
          # And unifiedEdges has at least the oracle's edge count.
          unifiedAtLeastOracleCount = builtins.length unified >= builtins.length oracle;
        };
        expected = {
          oracleHasNoRewalk = true;
          unifiedSupersetOfOracle = true;
          unifiedAtLeastOracleCount = true;
        };
      }
    );

    # ===== (3) per-host edges present (instantiate-style topology) ===========
    # A flake-level resolve with an instantiate spec: unifiedEdges carries the
    # per-host default-fold + route edges (the mkInstantiateEdges projection) that
    # the top-level oracle set does not derive (the oracle has the flake-output
    # instantiate edge; the per-host fold edges are the NEW additive surface).
    test-perhost-edges-present = denTest (
      { den, lib, ... }:
      let
        flakeResult = den.lib.aspects.resolveWithPaths "flake" (den.lib.resolveEntity "flake" { });
        unified = flakeResult.unifiedEdges;
        # A per-host default-fold edge: merge, P=[], targeting the host root's
        # nixos. The oracle's top-level folds target the flake/system roots, so a
        # host-rooted merge fold is the per-host projection's signature.
        hostRootedFolds = lib.filter (
          e:
          e.mode == "merge"
          && e.path == [ ]
          && e.source ? collected
          && e.target ? root
          && lib.hasInfix "host" e.target.root
        ) unified;
      in
      {
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
        den.hosts.x86_64-linux.igloo.users = { };
        den.aspects.igloo.nixos.networking.hostName = "igloo";

        # The per-host projection surfaced at least one host-rooted default fold.
        expr = hostRootedFolds != [ ];
        expected = true;
      }
    );
  };
}
