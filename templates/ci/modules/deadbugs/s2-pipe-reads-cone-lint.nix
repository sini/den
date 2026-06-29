# Fleet Seam S2 — pipe.reads cone-expander + unscoped-collect config-dep lint.
#
# An OPEN (config-dependent) cross-host emit — one collected via
# pipe.collect/collectAll or pushed via pipe.broadcast whose value reads the
# producer's `config` — must DECLARE the config-field cone it reads with a
# sibling `pipe.reads [ … ]` stage. "Always-true predicate" is undetectable in
# Nix (a predicate is opaque), so the guard is STRUCTURAL: config-dependent +
# no `reads` ⇒ the unscoped fleet-wide shape that forces every peer's full
# config ⇒ rejected at resolution. A declared cone (a) restricts the peer-config
# view the emit resolves against to exactly the declared paths and (b) returns
# the real peer value byte-identically for those paths (laziness already scoped
# the read; the cone only enforces). An OUT-OF-CONE read fails loud — that is
# the cone's teeth and the source of trust for the affected-set / class-share.
{ denTest, ... }:
{
  flake.tests.s2-pipe-reads-cone-lint = {

    # THE LINT (the keeper / the synth `globalTrigger` shape): a config-dependent
    # emit collected via an UNSCOPED collectAll with NO pipe.reads is rejected.
    # iceberg emits a config-derived host-marks; igloo collectAll's it without a
    # cone ⇒ forcing the collected value throws the lint.
    test-configdep-collectall-without-reads-throws = denTest (
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

        den.aspects.set-host.nixos =
          { host, ... }:
          {
            networking.hostName = host.name;
          };

        # UNSCOPED open emit: collectAll a config-dependent peer emit, NO reads.
        den.policies.collect-marks = _: [
          (pipe.from "host-marks" [ (pipe.collectAll ({ host, ... }: true)) ])
        ];

        # iceberg emits a config-dependent host-marks (reads its nixos config).
        den.aspects.iceberg.host-marks = { config, ... }: [ "m-${config.networking.hostName}" ];
        den.aspects.iceberg.includes = [ den.aspects.set-host ];

        den.aspects.igloo.includes = [
          den.aspects.set-host
          den.policies.collect-marks
        ];
        den.aspects.igloo.nixos =
          { host-marks, lib, ... }:
          {
            networking.search = lib.sort (a: b: a < b) host-marks;
          };

        # Forcing the collected pipe value triggers resolveEntry's lint → throw.
        expr = !(builtins.tryEval (builtins.deepSeq igloo.networking.search null)).success;
        expected = true;
      }
    );

    # POSITIVE PATH: the SAME emit with a declared `pipe.reads` cone resolves —
    # and the declared path returns the real peer value byte-identically (the
    # cone bounds, it does not change, the value). igloo's own emit (resolved via
    # __configThunk in its own fixpoint) + iceberg's cone-restricted collected
    # emit ⇒ both marks present.
    test-reads-declared-resolves = denTest (
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

        den.aspects.set-host.nixos =
          { host, ... }:
          {
            networking.hostName = host.name;
          };

        # Declared cone: the collected emit reads exactly config.networking.hostName.
        den.policies.collect-marks = _: [
          (pipe.from "host-marks" [
            (pipe.reads [ "networking.hostName" ])
            (pipe.collectAll ({ host, ... }: true))
          ])
        ];

        den.aspects.iceberg.host-marks = { config, ... }: [ "m-${config.networking.hostName}" ];
        den.aspects.iceberg.includes = [ den.aspects.set-host ];

        den.aspects.igloo.host-marks = { config, ... }: [ "m-${config.networking.hostName}" ];
        den.aspects.igloo.includes = [
          den.aspects.set-host
          den.policies.collect-marks
        ];
        den.aspects.igloo.nixos =
          { host-marks, lib, ... }:
          {
            networking.search = lib.sort (a: b: a < b) host-marks;
          };

        expr = igloo.networking.search;
        expected = [
          "m-iceberg"
          "m-igloo"
        ];
      }
    );

    # THE TEETH: a declared cone that does NOT cover what the emit reads. The cone
    # declares networking.domain; iceberg's emit reads networking.hostName — an
    # out-of-cone field ⇒ absent in the restricted view ⇒ throws on read.
    test-out-of-cone-read-throws = denTest (
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

        # Both fields exist on the peer; only `domain` is in the declared cone.
        den.aspects.set-host.nixos =
          { host, ... }:
          {
            networking.hostName = host.name;
            networking.domain = host.name;
          };

        # Cone declares networking.domain, but the emit reads networking.hostName.
        den.policies.collect-marks = _: [
          (pipe.from "host-marks" [
            (pipe.reads [ "networking.domain" ])
            (pipe.collectAll ({ host, ... }: true))
          ])
        ];

        den.aspects.iceberg.host-marks = { config, ... }: [ "m-${config.networking.hostName}" ];
        den.aspects.iceberg.includes = [ den.aspects.set-host ];

        den.aspects.igloo.includes = [
          den.aspects.set-host
          den.policies.collect-marks
        ];
        den.aspects.igloo.nixos =
          { host-marks, lib, ... }:
          {
            networking.search = lib.sort (a: b: a < b) host-marks;
          };

        # The cone exposes only networking.domain, so reading networking.hostName
        # throws Nix's natural "attribute missing" — uncatchable by tryEval, so
        # asserted via the harness's expectedError mechanism (the teeth).
        expr = igloo.networking.search;
        expectedError = {
          type = "EvalError";
          msg = "hostName";
        };
      }
    );
  };
}
