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

    # 7. Root-scope entity arg → INERT (carrier removed @ this commit; rule: root
    # entity arg → inert). The formal rule: a parametric entity arg at a scope
    # whose entity kind is NEITHER able to bind it from ctx NOR an ancestor of it
    # is misplaced → whole aspect inert, silently. The root (flake) scope has NO
    # entity kind, so a `{ user, ... }` aspect there is strictly inert.
    #
    # Root-scope path: top-level resolution starts at the `flake` entity
    # (modules/outputs.nix: resolveEntity "flake" {}), whose includes are
    # `den.schema.flake.includes` (flake is a non-entity routing kind). That
    # scope is the rootScopeId with NO scopeEntityKind entry, so bind.nix sees
    # scopeKind == null: isDescendantOf is false, the `user` arg is misplaced →
    # inert. Previously this rode the cross-scope defer carrier (push-scope
    # deferred inheritance + walkDeferred refire); that carrier is now removed.
    test-root-scope-descendant-arg-inert = denTest (
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
        # Inert: root scope has no entity kind, so the { user } aspect is
        # misplaced. Neither class is delivered to descendants.
        expected = {
          hostFunny = [ ];
          tuxDirenv = false;
          pinguDirenv = false;
        };
      }
    );

  };
}
