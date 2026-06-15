# fx-edge-parity — the Task 19 cross-pipeline parity gate. Exercises the
# `assertEdgeParity` helper (nix/lib/aspects/fx/edges/parity.nix) over a corpus of
# the parity-critical delivery-edge topologies (spawn, instantiate/fleet,
# isolated-guest, plain host+user — the same topologies the unification gate and
# the oracle-production differential cover).
#
# Two flavours of assertion:
#
#   (1) IDENTITY GATE (per corpus topology) — diff a trace against ITSELF. A trace
#       is trivially parity-equal to itself, so this is NOT testing edge logic; it
#       proves three things at once:
#         - the harness is sound (a self-diff yields parity == true, empty deltas);
#         - the corpus topologies resolve (r.edgeTrace evaluates);
#         - each trace is NON-EMPTY (matched != [] → there is real content to diff,
#           so the gate is not vacuously green on an empty trace).
#
#   (2) NEGATIVE CONTROL — on a spawn topology, diff the production `edgeTrace`
#       against the legacy `legacyEdgeTrace` (the rewalk + suppressed-twin
#       re-derivation). These genuinely diverge (the spawn rewalk arm vs the real
#       surfaced fold edges), so `parity == false`. This proves `assertEdgeParity`
#       actually DETECTS divergence — without it, the identity gate alone could pass
#       on a helper that always returns parity == true.
#
# `just ci fx-edge-parity` runs this suite.
{ denTest, lib, ... }:
let
  # The fleet → hosts include policy shared by the spawn + instantiate topologies
  # (verbatim from fx-edge-unification-gate.nix): a flake-level resolve that fans
  # out to each host with an instantiate spec.
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

  # The identity-gate assertion, shared by every corpus topology. `edges` is the
  # trace under test; a trace is parity-equal to itself with empty asymmetric
  # deltas, and matched must be non-empty (proving the trace carries content).
  identityGate =
    den: edges:
    let
      diff = den.lib.aspects.fx.edges.parity.assertEdgeParity {
        expected = edges;
        actual = edges;
      };
    in
    {
      parity = diff.parity;
      matchedNonEmpty = diff.matched != [ ];
      noMissing = diff.missingFromActual == [ ];
      noExtra = diff.extraInActual == [ ];
    };

  identityExpected = {
    parity = true;
    matchedNonEmpty = true;
    noMissing = true;
    noExtra = true;
  };
in
{
  flake.tests.fx-edge-parity = {

    # ===== IDENTITY GATE: SPAWN topology (flake-level, host-aspects battery) ==
    test-identity-spawn = denTest (
      { den, lib, ... }:
      let
        r = den.lib.aspects.resolveWithPaths "flake" (den.lib.resolveEntity "flake" { });
      in
      fleetSetup den lib
      // {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.aspects.igloo.homeManager.home.sessionVariables.X = "y";
        den.aspects.tux.includes = [ den.batteries.host-aspects ];
        den.aspects.igloo.nixos.networking.hostName = "igloo";

        expr = identityGate den r.edgeTrace;
        expected = identityExpected;
      }
    );

    # ===== IDENTITY GATE: INSTANTIATE / fleet topology (flake-level) ==========
    test-identity-instantiate = denTest (
      { den, lib, ... }:
      let
        r = den.lib.aspects.resolveWithPaths "flake" (den.lib.resolveEntity "flake" { });
      in
      fleetSetup den lib
      // {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.aspects.igloo.nixos.networking.hostName = "igloo";

        expr = identityGate den r.edgeTrace;
        expected = identityExpected;
      }
    );

    # ===== IDENTITY GATE: ISOLATED-GUEST topology (host-level route) ==========
    test-identity-isolated-guest = denTest (
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

        expr = identityGate den r.edgeTrace;
        expected = identityExpected;
      }
    );

    # ===== IDENTITY GATE: PLAIN host+user (no spawn, host-level) ==============
    test-identity-plain = denTest (
      { den, ... }:
      let
        r = den.lib.aspects.resolveWithPaths "nixos" (
          den.lib.resolveEntity "host" { host = den.hosts.x86_64-linux.igloo; }
        );
      in
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.aspects.igloo.nixos.networking.hostName = "igloo";

        expr = identityGate den r.edgeTrace;
        expected = identityExpected;
      }
    );

    # ===== NEGATIVE CONTROL: spawn production vs legacy diverges ==============
    # Diffing the production edgeTrace against the legacy legacyEdgeTrace on a spawn
    # topology MUST yield parity == false (the rewalk arm + suppressed twins vs the
    # real surfaced fold edges) — proving the helper detects divergence and the
    # identity gate is not vacuous.
    test-negative-control-spawn = denTest (
      { den, lib, ... }:
      let
        r = den.lib.aspects.resolveWithPaths "flake" (den.lib.resolveEntity "flake" { });
        diff = den.lib.aspects.fx.edges.parity.assertEdgeParity {
          expected = r.edgeTrace;
          actual = r.legacyEdgeTrace;
        };
      in
      fleetSetup den lib
      // {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.aspects.igloo.homeManager.home.sessionVariables.X = "y";
        den.aspects.tux.includes = [ den.batteries.host-aspects ];
        den.aspects.igloo.nixos.networking.hostName = "igloo";

        expr = diff.parity;
        expected = false;
      }
    );
  };
}
