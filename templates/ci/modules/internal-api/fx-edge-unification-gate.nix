# fx-edge-unification-gate — the lighter Task-16 gate. For the parity-critical
# topologies it proves the unified delivery-edge set is BOTH complete and validly
# orderable, and that the shared toposort entry is loud on a real cycle:
#
#   (1) COMPLETENESS — unifiedEdges ⊇ (edgeTrace MINUS its rewalk-source edges),
#       i.e. every non-rewalk oracle edge survives, PLUS the newly-surfaced edges
#       (the spawn route/default-fold edges for spawn topologies; the per-host
#       default-fold + route edges for instantiate topologies).
#
#   (2) VALID ORDER — `topoSortEdges unifiedEdges` SUCCEEDS (does not throw → the
#       unified set is acyclic and every dep is satisfiable) AND is a permutation
#       of unifiedEdges (identical edge multiset by the normalized sort key). Plus
#       a producer-before-merge spot-check: a route/provides producer edge appears
#       at a SMALLER index than the default-fold merge edge of the same class+root
#       that reads it.
#
#   (3) CYCLE THROWS — a deliberately-cyclic edge set (a synthesize 2-cycle, as in
#       fx-toposort-edges.nix) passed through the SAME `topoSortEdges` entry the
#       unified set uses THROWS the loud cycle error.
#
# `unifiedEdges` is reached the way fx-unified-edges.nix reaches it: it sits beside
# `edgeTrace` on the resolveWithPaths result. The spawn + instantiate topologies
# resolve at FLAKE level (the drain-fold spawn + mkInstantiateEdges projections
# only surface there — at host level the host is the ctx-seeded root, so those arms
# are no-ops, spec 16.3).
#
# `just ci fx-edge-unification-gate` runs this suite.
{ denTest, lib, ... }:
let
  # Stable sort key mirroring edges/edge.nix edgeSortKey (T, P, S, M), so two edge
  # lists are compared as normalized MULTISETS regardless of construction order.
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

  # Completeness: every edge in `sub` is present in `super` (by normalized key).
  keySet = edges: lib.genAttrs (map edgeKey edges) (_: true);
  isSubset = sub: super: lib.all (e: (keySet super) ? ${edgeKey e}) sub;

  # Multiset equality by sorted key lists (a permutation has the same edges in any
  # order). Counts duplicates correctly (sorted-list compare, not set compare).
  sameMultiset =
    a: b: lib.sort (x: y: x < y) (map edgeKey a) == lib.sort (x: y: x < y) (map edgeKey b);

  # The fleet → hosts include policy shared by the spawn + instantiate topologies
  # (verbatim from fx-unified-edges.nix / delivery-edges.nix): a flake-level resolve
  # that fans out to each host with an instantiate spec.
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

  # The valid-order assertion, shared by every topology. `unified` is the unified
  # edge set under test. Returns the booleans the gate pins:
  #   sortSucceeds            — topoSortEdges did not throw (acyclic + satisfiable).
  #   sortIsPermutation       — the sorted output is the same multiset as the input.
  #   producerBeforeMerge     — at least one producer (route/provides nest edge)
  #                             precedes the default-fold merge of the same root+class
  #                             that READS its cell, and none of those producer/merge
  #                             pairs is mis-ordered.
  validOrder =
    den: unified:
    let
      inherit (den.lib.aspects.fx.edges) toposort;
      ordered = toposort.topoSortEdges unified;
      sortSucceeds = builtins.deepSeq ordered true;
      indexByKey = lib.listToAttrs (lib.imap0 (i: e: lib.nameValuePair (edgeKey e) i) ordered);
      # Producer = a nest/nest-verbatim edge whose target is a root (not a flake
      # output): it WRITES the (root, class) cell.
      producers = lib.filter (
        e: (e.mode == "nest" || e.mode == "nest-verbatim") && e.target ? root
      ) ordered;
      # Reading default folds = merge edges with collectedScopes (the final
      # extraction at a root reads every subtree-scope bucket at its class).
      readingFolds = lib.filter (
        e: e.mode == "merge" && e.target ? root && e.annotations ? collectedScopes
      ) ordered;
      # A (producer, fold) pair where the fold READS the producer's cell: the
      # producer's target root is among the fold's collectedScopes AND the classes
      # match. The producer must come strictly before the fold.
      pairs = builtins.concatLists (
        map (
          p:
          lib.filter (f: f != null) (
            map (
              f:
              if
                f.target.class == p.target.class
                && builtins.elem p.target.root (f.annotations.collectedScopes or [ ])
              then
                {
                  producer = p;
                  fold = f;
                }
              else
                null
            ) readingFolds
          )
        ) producers
      );
      pairOk = pr: indexByKey.${edgeKey pr.producer} < indexByKey.${edgeKey pr.fold};
    in
    {
      inherit sortSucceeds;
      sortIsPermutation = sameMultiset ordered unified;
      # At least one real producer→reading-fold pair, and EVERY such pair correctly
      # ordered (producer strictly before the merge that reads it).
      producerBeforeMerge = pairs != [ ] && lib.all pairOk pairs;
    };
in
{
  flake.tests.fx-edge-unification-gate = {

    # ===== SPAWN topology (flake-level, host-aspects battery) ============
    # A user under a host re-applies a host-schema homeManager projection; the
    # host-aspects battery emits a spawn marker. The oracle renders ONE rewalk edge;
    # the unified set drops it and surfaces the spawn's real delivered edges. We
    # prove: oracle-minus-rewalk ⊆ unified, the surfaced spawn HM fold is present,
    # the unified set has no rewalk arm, AND the unified set sorts to a valid
    # permutation.
    test-spawn-complete-and-ordered = denTest (
      { den, lib, ... }:
      let
        r = den.lib.aspects.resolveWithPaths "flake" (den.lib.resolveEntity "flake" { });
        oracle = r.edgeTrace;
        unified = r.unifiedEdges;
        oracleNoRewalk = lib.filter (e: !(e.source ? rewalk)) oracle;
        order = validOrder den unified;
      in
      fleetSetup den lib
      // {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.aspects.igloo.homeManager.home.sessionVariables.X = "y";
        den.aspects.tux.includes = [ den.batteries.host-aspects ];
        den.aspects.igloo.nixos.networking.hostName = "igloo";

        expr = {
          # (1) completeness: every non-rewalk oracle edge survives in unified.
          completenessOracleMinusRewalk = isSubset oracleNoRewalk unified;
          # the unified set has surfaced the spawn arm (no rewalk left).
          unifiedHasNoRewalk = lib.all (e: !(e.source ? rewalk)) unified;
          # the surfaced spawn delivers a homeManager default fold into the user
          # root — a concrete edge the oracle's single rewalk arm collapsed away.
          surfacedSpawnHmFold = lib.any (
            e:
            e.mode == "merge"
            && e.path == [ ]
            && e.source ? collected
            && e.source.collected.class == "homeManager"
            && e.target ? root
            && lib.hasInfix "user" e.target.root
            && e.target.class == "homeManager"
          ) unified;
          # (2) valid order.
          inherit (order) sortSucceeds sortIsPermutation producerBeforeMerge;
        };
        expected = {
          completenessOracleMinusRewalk = true;
          unifiedHasNoRewalk = true;
          surfacedSpawnHmFold = true;
          sortSucceeds = true;
          sortIsPermutation = true;
          producerBeforeMerge = true;
        };
      }
    );

    # ===== PLAIN host+user (no spawn) ====================================
    # No spawn marker → the oracle has no rewalk arm, so the WHOLE oracle set must
    # survive in unified (completeness on the full set). Resolved at host level
    # (the per-host/instantiate arms are flake-level only, so this is the pure
    # top-level mechanism set).
    test-plain-complete-and-ordered = denTest (
      { den, lib, ... }:
      let
        r = den.lib.aspects.resolveWithPaths "nixos" (
          den.lib.resolveEntity "host" { host = den.hosts.x86_64-linux.igloo; }
        );
        oracle = r.edgeTrace;
        unified = r.unifiedEdges;
        order = validOrder den unified;
      in
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.aspects.igloo.nixos.networking.hostName = "igloo";

        expr = {
          # No spawn → oracle has no rewalk edge to drop.
          oracleHasNoRewalk = lib.all (e: !(e.source ? rewalk)) oracle;
          # (1) completeness: the full oracle set survives in unified.
          completenessFullOracle = isSubset oracle unified;
          # (2) valid order.
          inherit (order) sortSucceeds sortIsPermutation producerBeforeMerge;
        };
        expected = {
          oracleHasNoRewalk = true;
          completenessFullOracle = true;
          sortSucceeds = true;
          sortIsPermutation = true;
          producerBeforeMerge = true;
        };
      }
    );

    # ===== INSTANTIATE / multi-host (flake-level fleet) ==================
    # A flake-level fleet resolve with an instantiate spec: unified carries the
    # per-host default-fold + route edges (the mkInstantiateEdges projection) that
    # the top-level oracle does not derive. We prove: oracle-minus-rewalk ⊆ unified,
    # at least one host-rooted default fold is present (the per-host surface), AND
    # the unified set sorts to a valid permutation.
    test-instantiate-complete-and-ordered = denTest (
      { den, lib, ... }:
      let
        r = den.lib.aspects.resolveWithPaths "flake" (den.lib.resolveEntity "flake" { });
        oracle = r.edgeTrace;
        unified = r.unifiedEdges;
        oracleNoRewalk = lib.filter (e: !(e.source ? rewalk)) oracle;
        order = validOrder den unified;
        # A per-host default-fold edge: merge, P=[], targeting a host root's class.
        # The oracle's top-level folds target the flake/system roots, so a
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
      fleetSetup den lib
      // {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.aspects.igloo.nixos.networking.hostName = "igloo";

        expr = {
          # (1) completeness: every non-rewalk oracle edge survives.
          completenessOracleMinusRewalk = isSubset oracleNoRewalk unified;
          # the per-host projection surfaced at least one host-rooted default fold.
          perHostFoldPresent = hostRootedFolds != [ ];
          # (2) valid order.
          inherit (order) sortSucceeds sortIsPermutation producerBeforeMerge;
        };
        expected = {
          completenessOracleMinusRewalk = true;
          perHostFoldPresent = true;
          sortSucceeds = true;
          sortIsPermutation = true;
          producerBeforeMerge = true;
        };
      }
    );

    # ===== ISOLATED-GUEST topology (host-level, appendToParent route) ====
    # An isolated guest kind under the host: the guest gets its OWN default fold
    # (isolation = it is its own entity-root) and a nest-verbatim delivery route
    # (appendToParent, reinstantiate) into the host root. No spawn → full oracle
    # set survives. We prove completeness on the full oracle set AND valid order
    # (the verbatim route producer, an appendToParent edge writing the host cell,
    # is among the producer→fold pairs the ordering spot-check covers).
    test-isolated-guest-complete-and-ordered = denTest (
      { den, lib, ... }:
      let
        guestEntity = {
          name = "guest";
          system = "x86_64-linux";
          class = "nixos";
          intoAttr = [ ];
          users = { };
          aspect = den.aspects.guest-aspect;
        };
        deliverPolicy = den.lib.policy.mkPolicy "deliver-iso" (
          { ... }@args:
          lib.optionals (!(args ? user) && !(args ? home)) [
            (den.lib.policy.route {
              fromClass = "nixos";
              intoClass = "nixos";
              collectSubtree = true;
              appendToParent = true;
              reinstantiate = true;
              path = [
                "microvm"
                "vms"
                "guest"
              ];
            })
          ]
        );
        r = den.lib.aspects.resolveWithPaths "nixos" (
          den.lib.resolveEntity "host" { host = den.hosts.x86_64-linux.igloo; }
        );
        oracle = r.edgeTrace;
        unified = r.unifiedEdges;
        order = validOrder den unified;
      in
      {
        den.hosts.x86_64-linux.igloo.users = { };
        den.schema.iso-kind = {
          isEntity = true;
          parent = "host";
          isolated = true;
        };
        den.policies.resolve-iso-child =
          { host, ... }:
          lib.optionals (host.name == "igloo") [
            (den.lib.policy.resolve.to.withIncludes "iso-kind" [ deliverPolicy ] { iso-kind = guestEntity; })
          ];
        den.schema.host.includes = [ den.policies.resolve-iso-child ];
        den.aspects.guest-aspect.nixos.boot.kernelModules = [ "g" ];
        den.aspects.igloo.nixos.networking.hostName = "igloo";

        expr = {
          # No spawn → oracle has no rewalk edge.
          oracleHasNoRewalk = lib.all (e: !(e.source ? rewalk)) oracle;
          # (1) completeness: the full oracle set survives in unified.
          completenessFullOracle = isSubset oracle unified;
          # The verbatim delivery route (the isolation producer) is in the set.
          verbatimRoutePresent = lib.any (e: e.mode == "nest-verbatim") unified;
          # (2) valid order.
          inherit (order) sortSucceeds sortIsPermutation producerBeforeMerge;
        };
        expected = {
          oracleHasNoRewalk = true;
          completenessFullOracle = true;
          verbatimRoutePresent = true;
          sortSucceeds = true;
          sortIsPermutation = true;
          producerBeforeMerge = true;
        };
      }
    );

    # ===== CYCLE throws ==================================================
    # A synthesize 2-cycle (F1 a→b writes (s,b) reads all "a"; F2 b→a writes (s,a)
    # reads all "b") through the SAME `topoSortEdges` entry the unified set uses
    # must THROW the loud cycle error (mutual dependency → no Kahn-ready edge).
    test-cycle-throws = denTest (
      { den, ... }:
      let
        inherit (den.lib.aspects.fx.edges) toposort edge;
        f1 = edge.mkEdge {
          source = edge.synthesize "F1" "a" "b";
          target = edge.rootTarget "s" "b";
          path = [ ];
          mode = "nest";
        };
        f2 = edge.mkEdge {
          source = edge.synthesize "F2" "b" "a";
          target = edge.rootTarget "s" "a";
          path = [ ];
          mode = "nest";
        };
        result = builtins.tryEval (
          builtins.deepSeq (toposort.topoSortEdges [
            f1
            f2
          ]) "no-throw"
        );
      in
      {
        expr = result.success;
        expected = false;
      }
    );
  };
}
