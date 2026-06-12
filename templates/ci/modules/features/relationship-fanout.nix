# Synchronous relationship fan-out: a parametric aspect at scope S destructuring
# an entity-kind arg K_a that is a schema-DAG DESCENDANT of S's kind fans out
# over S's K_a-children, refiring bound to each, EMITTING AT S. Class content
# foreign to S (e.g. homeManager on a host scope) becomes inert.
#
# A misplaced entity arg (K_a neither in-ctx nor a descendant) → whole aspect
# inert, silently. Zero children → inert. Fan-out is synchronous inside `bind`;
# entity args never reach `defer`.
{ denTest, lib, ... }:
{
  flake.tests.relationship-fanout = {

    # 1. Per-user distinct content lands on the host once per user.
    test-per-user-distinct-lands-on-host = denTest (
      {
        den,
        igloo,
        lib,
        ...
      }:
      {
        den.hosts.x86_64-linux.igloo.users = {
          tux = { };
          pingu = { };
        };

        den.aspects.igloo.nixos.options.funny = lib.mkOption {
          default = [ ];
          type = lib.types.listOf lib.types.str;
        };

        # { user } at host scope: user is a descendant of host → fan out.
        den.aspects.igloo.includes = [
          (
            { user, ... }:
            {
              nixos.funny = [ "nixos ${user.name}" ];
            }
          )
        ];

        expr = lib.sort lib.lessThan igloo.funny;
        expected = [
          "nixos pingu"
          "nixos tux"
        ];
      }
    );

    # 2. Dedup guard: identical STATIC content per user appears TWICE in the
    # merged list (the per-child __ctxId tag must keep the two fan-out instances
    # distinct so neither collapses).
    test-identical-static-appears-per-user = denTest (
      {
        den,
        igloo,
        lib,
        ...
      }:
      {
        den.hosts.x86_64-linux.igloo.users = {
          tux = { };
          pingu = { };
        };

        den.aspects.igloo.nixos.options.funny = lib.mkOption {
          default = [ ];
          type = lib.types.listOf lib.types.str;
        };

        den.aspects.igloo.includes = [
          (
            { user, ... }:
            {
              nixos.funny = [ "static" ];
            }
          )
        ];

        expr = lib.sort lib.lessThan igloo.funny;
        expected = [
          "static"
          "static"
        ];
      }
    );

    # 3. homeManager content in a HOST-scope fan-out aspect is class-local to the
    # host (which does not resolve homeManager) → inert; it must NOT land on the
    # users' HM eval. The old cross-scope defer carrier is starved (entity args
    # bypass defer), so the leak is gone.
    test-homemanager-content-inert-at-host-scope = denTest (
      {
        den,
        tuxHm,
        pinguHm,
        ...
      }:
      {
        den.hosts.x86_64-linux.igloo.users = {
          tux = { };
          pingu = { };
        };

        den.aspects.igloo.includes = [
          (
            { user, ... }:
            {
              homeManager.programs.direnv.enable = true;
            }
          )
        ];

        expr = [
          tuxHm.programs.direnv.enable
          pinguHm.programs.direnv.enable
        ];
        # Inert: host scope resolves no homeManager class. Users never receive it.
        expected = [
          false
          false
        ];
      }
    );

    # 4. Misplaced: a fresh entity kind with no parent, destructured at host
    # scope → inert, no error, host still evaluates.
    test-misplaced-entity-arg-inert = denTest (
      {
        den,
        igloo,
        lib,
        ...
      }:
      {
        den.schema.gadget.isEntity = true;

        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.igloo = {
          nixos.networking.hostName = "igloo";
          includes = [
            (
              { gadget, ... }:
              {
                nixos.networking.hostName = "should-not-appear";
              }
            )
          ];
        };

        expr = igloo.networking.hostName;
        expected = "igloo";
      }
    );

    # 5. Zero children: host with no users + { user } aspect → inert, no error.
    test-zero-children-inert = denTest (
      {
        den,
        igloo,
        ...
      }:
      {
        den.hosts.x86_64-linux.igloo = { };

        den.aspects.igloo = {
          nixos.networking.hostName = "igloo";
          includes = [
            (
              { user, ... }:
              {
                nixos.networking.hostName = "should-not-appear";
              }
            )
          ];
        };

        expr = igloo.networking.hostName;
        expected = "igloo";
      }
    );

    # 6. Composition of in-ctx + descendant: { host, user } at HOST scope. host is
    # in ctx (bound once), user is a descendant (fan-out). Per-user distinct
    # content carrying the bound host name lands on the host.
    test-host-in-ctx-user-descendant = denTest (
      {
        den,
        igloo,
        lib,
        ...
      }:
      {
        den.hosts.x86_64-linux.igloo.users = {
          tux = { };
          pingu = { };
        };

        den.aspects.igloo.nixos.options.funny = lib.mkOption {
          default = [ ];
          type = lib.types.listOf lib.types.str;
        };

        den.aspects.igloo.includes = [
          (
            { host, user, ... }:
            {
              nixos.funny = [ "${user.name}@${host.name}" ];
            }
          )
        ];

        expr = lib.sort lib.lessThan igloo.funny;
        expected = [
          "pingu@igloo"
          "tux@igloo"
        ];
      }
    );

    # 7. TRIPWIRE for carrier removal: this rides the dying cross-scope chain;
    # when push-scope inheritance + walkDeferred are removed, classify the flip
    # per the formal rule (root scope has no entity kind → strictly inert) and
    # update this expectation consciously.
    #
    # Root-scope path: the top-level resolution starts at the `flake` entity
    # (modules/outputs.nix: resolveEntity "flake" {}), whose includes are
    # `den.schema.flake.includes` (flake is a non-entity routing kind, so no
    # selfProvide). That scope is the rootScopeId with NO scopeEntityKind entry,
    # so in bind.nix `scopeKind == null` → the root-scope guard zeroes
    # entityMissing and the `{ user, ... }` aspect takes the DEFER path, NOT the
    # fan-out path. It is then inherited down through push-scope's
    # scopedDeferredIncludes (push-scope.nix:72-79) and refired by walkDeferred
    # once `user` is in scope at each user scope — the cross-scope carrier.
    #
    # CURRENT behavior (determined empirically): both classes are delivered to
    # the descendants. nixos content lands on the host once per user
    # ("root-saw <user>"), and homeManager content reaches each user's HM eval.
    # This is the carrier delivering, NOT the synchronous fan-out path.
    #
    # When the carrier is removed, the formal rule makes a root-scope entity arg
    # strictly inert (root scope has no entity kind to fan out over), so BOTH the
    # host funny list AND the per-user HM direnv flip to absent. Update both
    # expectations together at that point.
    test-root-scope-descendant-arg-tripwire = denTest (
      {
        den,
        igloo,
        tuxHm,
        pinguHm,
        lib,
        ...
      }:
      {
        den.hosts.x86_64-linux.igloo.users = {
          tux = { };
          pingu = { };
        };

        den.aspects.igloo.nixos.options.funny = lib.mkOption {
          default = [ ];
          type = lib.types.listOf lib.types.str;
        };

        # { user } aspect at the ROOT (flake) scope — NOT host scope. Verified to
        # take the defer path (scopeKind == null), not the fan-out path.
        den.schema.flake.includes = [
          (
            { user, ... }:
            {
              nixos.funny = [ "root-saw ${user.name}" ];
              homeManager.programs.direnv.enable = true;
            }
          )
        ];

        expr = {
          hostFunny = lib.sort lib.lessThan igloo.funny;
          tuxDirenv = tuxHm.programs.direnv.enable;
          pinguDirenv = pinguHm.programs.direnv.enable;
        };
        # Carrier-delivered (current). On carrier removal: hostFunny → [ ],
        # tuxDirenv → false, pinguDirenv → false.
        expected = {
          hostFunny = [
            "root-saw pingu"
            "root-saw tux"
          ];
          tuxDirenv = true;
          pinguDirenv = true;
        };
      }
    );

  };
}
