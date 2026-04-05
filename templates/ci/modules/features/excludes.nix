{ denTest, ... }:
{
  flake.tests.excludes = {

    # Entity-level: host excludes an aspect globally
    test-host-excludes-aspect = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo = {
          excludes = [ den.aspects.noisy ];
          users.tux = { };
        };
        den.aspects.igloo.includes = [ den.aspects.noisy ];
        den.aspects.noisy.nixos.networking.hostName = "NOISY";
        den.default.includes = [ den._.hostname ];

        expr = igloo.networking.hostName;
        expected = "igloo";
      }
    );

    # Entity-level: excluded aspect's transitive includes are also excluded
    test-host-excludes-transitive = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo = {
          excludes = [ den.aspects.parent ];
          users.tux = { };
        };
        den.aspects.igloo.includes = [ den.aspects.parent ];
        den.aspects.parent = {
          nixos.networking.hostName = "PARENT";
          includes = [ { nixos.networking.domain = "CHILD"; } ];
        };
        den.default.includes = [ den._.hostname ];

        expr = igloo.networking.hostName;
        expected = "igloo";
      }
    );

    # Entity-level: excluding non-existent aspect is a no-op
    test-host-excludes-nonexistent = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo = {
          excludes = [ { name = "does-not-exist"; } ];
          users.tux = { };
        };
        den.default.includes = [ den._.hostname ];

        expr = igloo.networking.hostName;
        expected = "igloo";
      }
    );

    # Aspect-level: subtree-scoped, siblings unaffected.
    test-aspect-excludes-subtree-only = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.shared.nixos.services.openssh.enable = true;

        den.aspects.wrapper-a = {
          excludes = [ den.aspects.shared ];
          includes = [ den.aspects.shared ];
          nixos.networking.domain = "wrapper-a-still-works";
        };

        den.aspects.wrapper-b = {
          includes = [ den.aspects.shared ];
        };

        den.aspects.igloo.includes = [
          den.aspects.wrapper-a
          den.aspects.wrapper-b
        ];

        expr = [
          igloo.services.openssh.enable
          igloo.networking.domain
        ];
        expected = [
          true
          "wrapper-a-still-works"
        ];
      }
    );

    # Aspect-level: excludes only affect the declaring aspect's subtree
    test-aspect-excludes-not-siblings = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.target.nixos.services.openssh.enable = true;

        den.aspects.excluder = {
          excludes = [ den.aspects.target ];
          nixos.networking.domain = "excluder-works";
        };

        den.aspects.igloo.includes = [
          den.aspects.excluder
          den.aspects.target
        ];

        expr = igloo.services.openssh.enable;
        expected = true;
      }
    );

    # Aspect-level: excludes propagate into nested includes
    test-aspect-excludes-nested = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.leaf.nixos.services.openssh.enable = true;

        den.aspects.middle = {
          includes = [ den.aspects.leaf ];
        };

        den.aspects.top = {
          excludes = [ den.aspects.leaf ];
          includes = [ den.aspects.middle ];
        };

        den.aspects.igloo.includes = [ den.aspects.top ];

        expr = igloo.services.openssh.enable;
        expected = false;
      }
    );

    # resolve' with exclude transform prunes nested aspect
    test-resolve-prime-excludes-nested = denTest (
      {
        den,
        lib,
        funnyNamesWith,
        ...
      }:
      {
        den.ctx.src.description = "source";
        den.ctx.src._.src =
          { x }:
          {
            funny.names = [ "root" ];
            includes = [
              {
                name = "mid";
                funny.names = [ "MID" ];
                includes = [
                  {
                    name = "leaf";
                    funny.names = [ "LEAF" ];
                  }
                ];
              }
            ];
          };

        expr =
          (funnyNamesWith {
            transforms = [ (den.lib.aspects.transforms.exclude [ { name = "leaf"; } ]) ];
          } (den.ctx.src { x = "a"; })).names;
        expected = [
          "MID"
          "root"
        ];
      }
    );

    # Aspect-level: host aspect excludes propagate into nested roles
    test-aspect-excludes-on-host = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.shared.nixos.services.openssh.enable = true;

        den.aspects.role-a.includes = [ den.aspects.shared ];
        den.aspects.role-b.includes = [ den.aspects.shared ];

        den.aspects.igloo = {
          excludes = [ den.aspects.shared ];
          includes = [
            den.aspects.role-a
            den.aspects.role-b
          ];
        };

        expr = {
          sshEnabled = igloo.services.openssh.enable;
        };
        expected = {
          sshEnabled = false;
        };
      }
    );

    # Excludes accept aspect references
    test-excludes-by-aspect-ref = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.unwanted.nixos.services.openssh.enable = true;
        den.aspects.igloo = {
          excludes = [ den.aspects.unwanted ];
          includes = [ den.aspects.unwanted ];
        };

        expr = igloo.services.openssh.enable;
        expected = false;
      }
    );

    # perHost-wrapped aspect gets name from submodule and can be excluded
    test-perHost-aspect-has-name = denTest (
      { den, ... }:
      {
        den.aspects.perhost-thing = den.lib.perHost (
          { host }:
          {
            nixos.networking.domain = "test";
          }
        );
        expr = den.aspects.perhost-thing.name;
        expected = "perhost-thing";
      }
    );

    # Entity-level: exclude a perHost-wrapped aspect
    test-host-excludes-perHost-wrapped = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo = {
          excludes = [ den.aspects.perhost-thing ];
          users.tux = { };
        };
        den.default.includes = [ den._.hostname ];
        den.aspects.perhost-thing = den.lib.perHost (
          { host }:
          {
            nixos.services.openssh.enable = true;
          }
        );
        den.aspects.igloo.includes = [ den.aspects.perhost-thing ];
        expr = igloo.services.openssh.enable;
        expected = false;
      }
    );

    # Aspect-level: exclude a perHost-wrapped aspect within subtree
    test-aspect-excludes-perHost-wrapped = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.default.includes = [ den._.hostname ];
        den.aspects.perhost-thing = den.lib.perHost (
          { host }:
          {
            nixos.services.openssh.enable = true;
          }
        );
        den.aspects.wrapper = {
          excludes = [ den.aspects.perhost-thing ];
          includes = [ den.aspects.perhost-thing ];
        };
        den.aspects.igloo.includes = [ den.aspects.wrapper ];
        expr = igloo.services.openssh.enable;
        expected = false;
      }
    );

    # Excludes propagate into forwarded class content
    test-excludes-propagate-into-forward = denTest (
      {
        den,
        lib,
        funnyNamesWith,
        ...
      }:
      {
        den.ctx.src.description = "source with forward";
        den.ctx.src._.src =
          { x }:
          {
            funny.names = [ "root" ];
            includes = [
              {
                name = "unwanted";
                funny.names = [ "EXCLUDED" ];
              }
              (
                { class, aspect-chain }:
                den._.forward {
                  each = lib.optional (class == "funny") class;
                  fromClass = _: "inner";
                  intoClass = _: "funny";
                  intoPath = _: [ ];
                  fromAspect = _: lib.head aspect-chain;
                }
              )
            ];
            inner.names = [ "forwarded" ];
          };

        expr =
          (funnyNamesWith {
            transforms = [ (den.lib.aspects.transforms.exclude [ { name = "unwanted"; } ]) ];
          } (den.ctx.src { x = "a"; })).names;
        expected = [
          "forwarded"
          "root"
        ];
      }
    );

    # Excluding an aspect cascades to its providers
    test-excludes-cascade-to-providers = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.default.includes = [ den._.hostname ];

        den.aspects.monitoring.nixos.services.prometheus.enable = true;
        den.aspects.monitoring.provides.node-exporter.nixos.services.openssh.enable = true;

        den.aspects.server = {
          includes = with den.aspects; [
            monitoring
            monitoring._.node-exporter
          ];
        };

        den.aspects.igloo = {
          excludes = [ den.aspects.monitoring ];
          includes = [ den.aspects.server ];
        };

        expr = {
          prometheus = igloo.services.prometheus.enable;
          ssh = igloo.services.openssh.enable;
        };
        expected = {
          prometheus = false;
          ssh = false;
        };
      }
    );

    # Provider excluded in one subtree still appears via independent include
    test-excludes-provider-scoped-to-subtree = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.default.includes = [ den._.hostname ];

        den.aspects.monitoring.nixos.services.prometheus.enable = true;
        den.aspects.monitoring.provides.node-exporter.nixos.services.openssh.enable = true;

        den.aspects.server = {
          excludes = [ den.aspects.monitoring ];
          includes = with den.aspects; [
            monitoring
            monitoring._.node-exporter
          ];
        };

        den.aspects.igloo.includes = with den.aspects; [
          server
          monitoring._.node-exporter
        ];

        expr = {
          prometheus = igloo.services.prometheus.enable;
          ssh = igloo.services.openssh.enable;
        };
        expected = {
          prometheus = false;
          ssh = true;
        };
      }
    );

    # End-to-end: __provider flows through provides -> includes -> exclude
    test-excludes-provider-end-to-end = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.default.includes = [ den._.hostname ];

        den.aspects.base = {
          nixos.networking.domain = "base";
          provides.extension.nixos.services.openssh.enable = true;
        };

        den.aspects.role = {
          includes = with den.aspects; [
            base
            base._.extension
          ];
        };

        den.aspects.igloo = {
          excludes = [ den.aspects.base ];
          includes = [ den.aspects.role ];
        };

        expr = {
          domain = igloo.networking.domain;
          ssh = igloo.services.openssh.enable;
        };
        expected = {
          domain = null;
          ssh = false;
        };
      }
    );

    # Angle bracket <aspect/provider> targets a specific provider
    test-angle-bracket-provider-exclude = denTest (
      {
        den,
        igloo,
        __findFile ? __findFile,
        ...
      }:
      let
        __findFile = den.lib.__findFile;
      in
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.default.includes = [ den._.hostname ];

        den.aspects.monitoring = {
          nixos.services.prometheus.enable = true;
          provides.node-exporter.nixos.services.openssh.enable = true;
          provides.alerting.nixos.services.resolved.enable = true;
        };

        den.aspects.server = {
          includes = with den.aspects; [
            monitoring
            monitoring._.node-exporter
            monitoring._.alerting
          ];
        };

        den.aspects.igloo = {
          excludes = [ <monitoring/node-exporter> ];
          includes = [ den.aspects.server ];
        };

        expr = {
          prometheus = igloo.services.prometheus.enable;
          ssh = igloo.services.openssh.enable;
          resolved = igloo.services.resolved.enable;
        };
        expected = {
          prometheus = true;
          ssh = false;
          resolved = true;
        };
      }
    );

  };
}
