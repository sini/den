# Fleet Seam S1 — per-sid lazy `hostConfigFor` laziness invariant.
#
# resolve.nix used to flip a fleet-wide `hasAnyConfigThunk` boolean on the mere
# PRESENCE of any `{ config, ... }` pipe thunk (even a purely host-LOCAL one),
# arming an eager `hostConfigs = mapAttrs (full nixosSystem) specsByHost` over
# the whole fleet. S1 splits that map into a structural host-scope key-SET
# (`hostConfigScopeIds`, membership only — forces nothing) plus an always-lazy
# memoized per-sid builder (`hostConfigFor`), so a config-dependent cross-host
# emit forces ONLY the peers it actually collects from.
#
# These two fixtures LOCK IN that invariant (both are green pre-change because
# the old map was lazy; their job is to keep it lazy as the global arming is
# removed). A peer whose nixos config field THROWS when built is the witness: if
# the resolver ever forces an UNRELATED / UNMATCHED peer's config, the throw
# fires and the test fails.
{ denTest, ... }:
{
  flake.tests.s1-per-sid-hostconfig-laziness = {

    # A host-LOCAL config-dependent emit (the real-axon age-secret shape: reads
    # `config`, consumed by the SAME host) must NOT cause any PEER config to be
    # built. iceberg's config throws if forced; reading igloo must resolve.
    test-local-configdep-emit-does-not-force-peer = denTest (
      {
        den,
        igloo,
        lib,
        ...
      }:
      let
        inherit (den.lib.policy) pipe;
      in
      {
        den.quirks.secret-marks.description = "Host-local config-derived secret marks (age-secret shape).";

        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.hosts.x86_64-linux.iceberg.users.alice = { };

        # Shared: every host sets its own hostName from the host record.
        den.aspects.set-host.nixos =
          { host, ... }:
          {
            networking.hostName = host.name;
          };

        # HOST-LOCAL config-dependent emit: reads `config`, consumed by the SAME
        # host's nixos (marked __configThunk, resolved in igloo's own evalModules).
        # NOT collected cross-host, so it must never reach a peer's config build.
        den.aspects.igloo.secret-marks = { config, ... }: [ "s-${config.networking.hostName}" ];
        den.aspects.igloo.nixos =
          { secret-marks, lib, ... }:
          {
            networking.search = lib.sort (a: b: a < b) secret-marks;
          };
        den.aspects.igloo.includes = [ den.aspects.set-host ];

        # POISON peer: iceberg's nixos config THROWS if built. With only a
        # host-LOCAL config-dep emit on igloo (no cross-host collect), S1's
        # invariant — a config-dep thunk's mere presence no longer arms
        # peer-config eval — means iceberg is never forced, so this stays dormant.
        den.aspects.iceberg.nixos =
          { ... }:
          {
            networking.domain = throw "den S1 regression: iceberg config forced by an unrelated host-local config-dep emit";
          };
        den.aspects.iceberg.includes = [ den.aspects.set-host ];

        expr = igloo.networking.search;
        expected = [ "s-igloo" ];
      }
    );

    # A config-dependent SCOPED collect (`pipe.collect`, siblings) must force ONLY
    # the matched peers, not every sibling. volcano is a sibling but is NOT matched
    # by igloo's predicate; its config field throws if built. The matched peer
    # (iceberg) resolves; volcano stays dormant.
    test-scoped-collect-forces-only-matched-peer = denTest (
      {
        den,
        igloo,
        lib,
        ...
      }:
      let
        inherit (den.lib.policy) pipe;
      in
      {
        den.quirks.host-marks.description = "Cross-host config-derived marks.";

        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.hosts.x86_64-linux.iceberg.users.alice = { };
        den.hosts.x86_64-linux.volcano.users.lava = { };

        # igloo SCOPED-collects host-marks from siblings whose host.name ==
        # "iceberg" ONLY — volcano is a sibling but is deliberately excluded.
        den.policies.collect-iceberg-marks = _: [
          (pipe.from "host-marks" [ (pipe.collect ({ host, ... }: host.name == "iceberg")) ])
        ];

        den.aspects.set-host.nixos =
          { host, ... }:
          {
            networking.hostName = host.name;
          };

        # The matched peer EMITS a host-marks config-thunk reading its own hostName.
        den.aspects.iceberg.host-marks = { config, ... }: [ "n-${config.networking.hostName}" ];
        den.aspects.iceberg.includes = [ den.aspects.set-host ];

        # POISON: volcano's host-marks config-thunk reads a field that THROWS.
        # igloo's scoped collect does NOT match volcano, so the resolver must build
        # ONLY iceberg's config (matched), never volcano's — this throw stays
        # dormant. A regression forcing every peer (or a list+elem membership that
        # mis-walks the owner chain) would trip it.
        den.aspects.volcano.nixos =
          { ... }:
          {
            networking.domain = throw "den S1 regression: an UNMATCHED scoped-collect peer (volcano) was forced";
          };
        den.aspects.volcano.host-marks = { config, ... }: [ "d-${config.networking.domain}" ];
        den.aspects.volcano.includes = [ den.aspects.set-host ];

        den.aspects.igloo.includes = [
          den.aspects.set-host
          den.policies.collect-iceberg-marks
        ];
        den.aspects.igloo.nixos =
          { host-marks, lib, ... }:
          {
            networking.search = lib.sort (a: b: a < b) host-marks;
          };

        expr = igloo.networking.search;
        expected = [ "n-iceberg" ];
      }
    );
  };
}
