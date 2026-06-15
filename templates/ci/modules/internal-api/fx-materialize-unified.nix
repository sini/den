# fx-materialize-unified — the Task-17 byte-equivalence proof. The ordered-
# dispatch engine (nix/lib/aspects/fx/edges/materialize-unified.nix) interleaves
# provides + routes in topoSortEdges order, reusing the EXISTING per-spec
# materializers; this suite proves it is byte-equivalent to the current
# phase2∘phase3 phase folds over the SAME live seed.
#
# Reached via the `materializeEquiv` surface on the resolveWithPaths result (a lazy
# thunk beside edgeTrace / unifiedEdges):
#   - materializeEquiv.phaseFold   — phase2∘phase3 (production order).
#   - materializeEquiv.unified     — materializeUnified { doFinalMerge = false }.
#   - materializeEquiv.unifiedMerged / .phaseFoldMerged — the doFinalMerge = true
#     pair (materializeUnified vs phaseFold-then-assembleSubtree).
#
# Class modules carry FUNCTIONS (`{ config, ... }: …` modules + the route nesting
# closures), which Nix cannot compare with `==` unless the references are identical
# — and the route closures are RE-CONSTRUCTED per fold, so `phaseFold == unified`
# would throw on a content list even when the delivery is identical. Fully
# EVALUATING the modules is also unsound here (a standalone freeform evalModules of
# a host class bucket hits undefined `nixpkgs` options).
#
# The proof is therefore TWO-PART, exactly matching Design B (order-only, reuse the
# same materializers):
#   (1) DISPATCH ORDER — the sequence of (kind, spec-identity) the unified engine
#       folds is IDENTICAL to phase2∘phase3 (all provides, in dedup order, then all
#       routes, in orderedKeptRoutes order). Since both paths run the SAME per-spec
#       materializers on the SAME seed, identical order ⇒ identical output by
#       construction. This is the load-bearing equivalence.
#   (2) STRUCTURAL FINGERPRINT — a function-tolerant deep walk of both
#       `{ classImports; perScope }` accumulators agrees: same attr keys, same list
#       lengths, same scalars, functions treated as opaque-equal leaves. This
#       guards (1) against a materializer that branches on fold position (it does
#       not — but the fingerprint catches any structural divergence the order proof
#       alone would miss).
# Together: identical dispatch order + identical structure over the same reused
# materializers == byte-equivalent delivery.
#
# `just ci fx-materialize-unified` runs this suite.
{ denTest, lib, ... }:
let
  # Function-tolerant structural fingerprint. Attrsets → sorted key list + per-key
  # fingerprint; lists → length + per-elem fingerprint; functions → opaque "<fn>"
  # (uninspectable, treated equal); scalars → their toString. NOT a content proof
  # on functions — paired with the dispatch-order proof which IS conclusive.
  fingerprint =
    v:
    if builtins.isFunction v then
      "<fn>"
    else if builtins.isList v then
      {
        __list = builtins.length v;
        items = map fingerprint v;
      }
    else if builtins.isAttrs v && !(lib.isDerivation v) then
      lib.mapAttrs (_: fingerprint) v
    else if lib.isDerivation v then
      "<drv:${v.name or "?"}>"
    else
      builtins.toString v;

  # The two accumulators agree iff their structural fingerprints are deep-equal.
  equivalent =
    e:
    let
      pf = e.phaseFold;
      un = e.unified;
    in
    {
      # (1) dispatch order — the identity sequence is identical.
      dispatchOrderEqual = e.phaseFoldDispatch == e.unifiedDispatch;
      # (2) structural fingerprint — classImports + perScope agree.
      classImportsEqual = fingerprint pf.classImports == fingerprint un.classImports;
      perScopeEqual = fingerprint pf.perScope == fingerprint un.perScope;
    };
  equivExpected = {
    dispatchOrderEqual = true;
    classImportsEqual = true;
    perScopeEqual = true;
  };
in
{
  flake.tests.fx-materialize-unified = {

    # ===== PLAIN host+user (default fold only) ===========================
    # No provides, no routes → the unified fold is the identity over the seed
    # (empty pair list); equivalence is the trivial-but-meaningful base case.
    test-plain-equivalent = denTest (
      { den, ... }:
      let
        r = den.lib.aspects.resolveWithPaths "nixos" (
          den.lib.resolveEntity "host" { host = den.hosts.x86_64-linux.igloo; }
        );
      in
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.aspects.igloo.nixos.networking.hostName = "igloo";

        expr = equivalent r.materializeEquiv;
        expected = equivExpected;
      }
    );

    # ===== PROVIDES topology =============================================
    # A policy.provide injects a module into the host's nixos class (P=[]) AND a
    # second provide nests at a path. Exercises applyOneProvide in the interleaved
    # fold vs the phase2 fold — both deduped, both into the source bucket.
    test-provides-equivalent = denTest (
      { den, ... }:
      let
        r = den.lib.aspects.resolveWithPaths "nixos" (
          den.lib.resolveEntity "host" { host = den.hosts.x86_64-linux.igloo; }
        );
      in
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.policies.provide-direct =
          { host, ... }:
          [
            (den.lib.policy.provide {
              class = host.class;
              module.networking.hostName = "provided";
            })
            (den.lib.policy.provide {
              class = host.class;
              module.value = "boxed";
              path = [ "provide-box" ];
            })
          ];
        den.default.includes = [ den.policies.provide-direct ];
        den.aspects.igloo.nixos.networking.domain = "local";

        expr = equivalent r.materializeEquiv;
        expected = equivExpected;
      }
    );

    # ===== ROUTE topology ================================================
    # A class route (path=[] merge) and a nested route (path≠[] nest) deliver a
    # custom source class into nixos. Exercises applySimpleRouteEdge in the
    # interleaved fold vs phase3, with simple routes reading the FROZEN seed
    # perScope in BOTH paths.
    test-routes-equivalent = denTest (
      { den, ... }:
      let
        r = den.lib.aspects.resolveWithPaths "nixos" (
          den.lib.resolveEntity "host" { host = den.hosts.x86_64-linux.igloo; }
        );
      in
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.classes.custom.description = "custom source class";
        den.classes.src.description = "nested source class";
        den.policies.route-both =
          { host, ... }:
          [
            (den.lib.policy.route {
              fromClass = "custom";
              intoClass = host.class;
              path = [ ];
            })
            (den.lib.policy.route {
              fromClass = "src";
              intoClass = host.class;
              path = [ "route-box" ];
            })
          ];
        den.default.includes = [ den.policies.route-both ];
        den.aspects.igloo = {
          nixos.networking.hostName = "igloo";
          custom.networking.domain = "routed";
          src.value = "nested";
        };

        expr = equivalent r.materializeEquiv;
        expected = equivExpected;
      }
    );

    # ===== PROVIDES + ROUTES interleaved =================================
    # Both mechanisms active: the interleaving (provides-before-routes among
    # independents) is the load-bearing case for byte-equivalence. The unified fold
    # must keep provides ahead of routes exactly as phase2∘phase3 does.
    test-provides-and-routes-equivalent = denTest (
      { den, ... }:
      let
        r = den.lib.aspects.resolveWithPaths "nixos" (
          den.lib.resolveEntity "host" { host = den.hosts.x86_64-linux.igloo; }
        );
      in
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.classes.custom.description = "custom source class";
        den.policies.provide-and-route =
          { host, ... }:
          [
            (den.lib.policy.provide {
              class = host.class;
              module.networking.hostName = "provided";
            })
            (den.lib.policy.route {
              fromClass = "custom";
              intoClass = host.class;
              path = [ ];
            })
          ];
        den.default.includes = [ den.policies.provide-and-route ];
        den.aspects.igloo = {
          custom.networking.domain = "routed";
        };

        expr = equivalent r.materializeEquiv;
        expected = equivExpected;
      }
    );

    # ===== ISOLATED-GUEST topology (appendToParent, reinstantiate) =======
    # An isolated guest kind with a nest-verbatim appendToParent route into the
    # host root (the gate's isolation canary). Exercises applySimpleRouteEdge's
    # nest-verbatim arm + appendToParent target scope in the interleaved fold.
    test-isolated-guest-equivalent = denTest (
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

        expr = equivalent r.materializeEquiv;
        expected = equivExpected;
      }
    );

    # ===== doFinalMerge = true ==========================================
    # materializeUnified { doFinalMerge = true } must equal phaseFold-then-
    # assembleSubtree (the final-extraction merge step, unchanged). Compared on the
    # provides+routes topology so the merge sees real content.
    test-final-merge-equivalent = denTest (
      { den, ... }:
      let
        r = den.lib.aspects.resolveWithPaths "nixos" (
          den.lib.resolveEntity "host" { host = den.hosts.x86_64-linux.igloo; }
        );
        e = r.materializeEquiv;
      in
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.classes.custom.description = "custom source class";
        den.policies.provide-and-route =
          { host, ... }:
          [
            (den.lib.policy.provide {
              class = host.class;
              module.networking.hostName = "provided";
            })
            (den.lib.policy.route {
              fromClass = "custom";
              intoClass = host.class;
              path = [ ];
            })
          ];
        den.default.includes = [ den.policies.provide-and-route ];
        den.aspects.igloo = {
          custom.networking.domain = "routed";
        };

        expr = {
          # assembleSubtree returns { class → [ modules ] }; the function-tolerant
          # fingerprint compares the two merged results structurally.
          mergeEqual = fingerprint e.unifiedMerged == fingerprint e.phaseFoldMerged;
        };
        expected = {
          mergeEqual = true;
        };
      }
    );

    # ===== exposeEdges = true (Task 18 capture) ==========================
    # materializeUnified { exposeEdges = true } ALSO carries the folded edge
    # records (`map (p: p.edge) orderedPairs`). Capture fidelity: the captured
    # `.edges` are the SAME SET as the constructor-built provides+route edges
    # over the same inputs — proven by sorting both via the edge sort key and
    # deep-comparing. Run on the provides+routes topology so both edge kinds
    # are present.
    #
    # ALSO proves the existing-mode invariant: with exposeEdges the accumulator
    # (everything but `.edges`) is byte-identical to the plain { doFinalMerge =
    # false } return — exposeEdges only ADDS the capture key.
    test-expose-edges-capture = denTest (
      { den, lib, ... }:
      let
        r = den.lib.aspects.resolveWithPaths "nixos" (
          den.lib.resolveEntity "host" { host = den.hosts.x86_64-linux.igloo; }
        );
        e = r.materializeEquiv;
        edgeMod = den.lib.aspects.fx.edges.edge;
        # Edges are pure data (target/source/path/mode/annotations) — compare the
        # captured fold edges to the constructor-built oracle as a SET by sorting
        # both via the edge sort key, then deep-comparing the sorted lists.
        sorted = edges: edgeMod.sortEdges edges;
        capturedSorted = sorted e.unifiedWithEdges.edges;
        oracleSorted = sorted e.oracleEdges;
      in
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.classes.custom.description = "custom source class";
        den.policies.provide-and-route =
          { host, ... }:
          [
            (den.lib.policy.provide {
              class = host.class;
              module.networking.hostName = "provided";
            })
            (den.lib.policy.route {
              fromClass = "custom";
              intoClass = host.class;
              path = [ ];
            })
          ];
        den.default.includes = [ den.policies.provide-and-route ];
        den.aspects.igloo = {
          custom.networking.domain = "routed";
        };

        expr = {
          # Capture fidelity: folded edges == constructor edges (as a sorted set).
          edgesMatchOracle = fingerprint capturedSorted == fingerprint oracleSorted;
          # The capture is non-empty here (one provide edge + one route edge).
          edgesNonEmpty = builtins.length e.unifiedWithEdges.edges > 0;
          # Existing-mode invariant: the accumulator (sans the added `edges` key)
          # is byte-identical to the plain no-exposeEdges return.
          accUnchanged =
            fingerprint (builtins.removeAttrs e.unifiedWithEdges [ "edges" ]) == fingerprint e.unified;
        };
        expected = {
          edgesMatchOracle = true;
          edgesNonEmpty = true;
          accUnchanged = true;
        };
      }
    );
  };
}
