{ denTest, ... }:
{
  flake.tests.class-module-partial-apply = {

    # Flat form: a nixos class module that requests `host` (a den context arg)
    # alongside standard module-system args. wrapClassModule detects `host`
    # in __ctx and pre-applies it, so the module evaluates successfully.
    test-flat-form-host-accessible = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.stages.test-flat = {
          includes = [ ];
          nixos =
            { host, config, ... }:
            {
              networking.hostName = host.name;
            };
        };

        den.policies.host-to-test-flat = {
          from = "host";
          to = "test-flat";
          resolve = _: [ { } ];
        };

        den.default.policies = [ "host-to-test-flat" ];

        expr = igloo.networking.hostName;
        expected = "igloo";
      }
    );

    # Two-layer form: the existing curried pattern still works unchanged.
    # The outer function is parametric (resolved by den), the inner is a
    # standard NixOS module — no wrapping needed.
    test-two-layer-form-unchanged = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.stages.test-twolayer = {
          includes = [
            (
              { host, ... }:
              {
                nixos =
                  { config, ... }:
                  {
                    networking.hostName = host.name;
                  };
              }
            )
          ];
        };

        den.policies.host-to-test-twolayer = {
          from = "host";
          to = "test-twolayer";
          resolve = _: [ { } ];
        };

        den.default.policies = [ "host-to-test-twolayer" ];

        expr = igloo.networking.hostName;
        expected = "igloo";
      }
    );

    # Multiple den args: both `host` and `user` are pre-applied from context.
    # The policy resolves with both host and user in the dispatch context,
    # so both are available for partial application in the class module.
    test-multiple-den-args = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.stages.test-multi-args = {
          includes = [ ];
          nixos =
            {
              host,
              user,
              config,
              ...
            }:
            {
              users.users.tux.description = "${host.name}/${user.name}";
            };
        };

        den.policies.host-to-test-multi-args = {
          from = "host";
          to = "test-multi-args";
          resolve = { host, ... }: map (user: { inherit host user; }) (builtins.attrValues host.users);
        };

        den.default.policies = [ "host-to-test-multi-args" ];

        expr = igloo.users.users.tux.description;
        expected = "igloo/tux";
      }
    );

    # Global collision policy config plumbing: verify den.config.classModuleCollisionPolicy
    # is settable and carries the configured value.
    test-global-collision-policy-plumbing = denTest (
      { den, ... }:
      {
        den.config.classModuleCollisionPolicy = "den-wins";

        expr = den.config.classModuleCollisionPolicy;
        expected = "den-wins";
      }
    );

    # Aspect meta.collisionPolicy is accessible through the aspect's meta.
    test-aspect-meta-collision-policy = denTest (
      { den, ... }:
      {
        den.aspects.test-cp = {
          meta.collisionPolicy = "class-wins";
        };

        expr = den.aspects.test-cp.meta.collisionPolicy;
        expected = "class-wins";
      }
    );

    # Functor module: an attrset with __functor passes through without wrapping
    # (builtins.isFunction returns false for functors). NixOS handles functors
    # natively, so the module still evaluates successfully.
    test-functor-module-passthrough = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.stages.test-functor = {
          includes = [ ];
          nixos = {
            __functor =
              self:
              { config, ... }:
              {
                networking.hostName = self.myName;
              };
            myName = "from-functor";
          };
        };

        den.policies.host-to-test-functor = {
          from = "host";
          to = "test-functor";
          resolve = _: [ { } ];
        };

        den.default.policies = [ "host-to-test-functor" ];

        expr = igloo.networking.hostName;
        expected = "from-functor";
      }
    );

    # functionArgs preservation: if the wrapped module evaluates successfully
    # through NixOS, setFunctionArgs worked — NixOS needs functionArgs to know
    # which args to pass. This is tested indirectly via the flat-form test above,
    # but we add an explicit test with a more complex arg pattern.
    test-function-args-preservation = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.stages.test-funcargs = {
          includes = [ ];
          nixos =
            {
              host,
              config,
              lib,
              pkgs,
              ...
            }:
            {
              users.users.tux.description = host.name;
            };
        };

        den.policies.host-to-test-funcargs = {
          from = "host";
          to = "test-funcargs";
          resolve = _: [ { } ];
        };

        den.default.policies = [ "host-to-test-funcargs" ];

        expr = igloo.users.users.tux.description;
        expected = "igloo";
      }
    );

    # Entity-level collisionPolicy plumbing: host entity carries collisionPolicy
    # from the schema definition and it is accessible.
    test-entity-collision-policy-plumbing = denTest (
      { den, ... }:
      {
        den.hosts.x86_64-linux.igloo = {
          collisionPolicy = "den-wins";
        };

        expr = den.hosts.x86_64-linux.igloo.collisionPolicy;
        expected = "den-wins";
      }
    );

    # Flat-form class module on a parametric aspect — the outer parametric
    # function receives host context, which propagates to __ctx, enabling
    # wrapClassModule to pre-apply host to the inner flat-form nixos module.
    test-flat-form-on-parametric-aspect = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.flat-aspect-test.includes = [
          (
            { host, ... }:
            {
              nixos =
                { host, config, ... }:
                {
                  networking.hostName = host.name;
                };
            }
          )
        ];
        den.aspects.igloo.includes = [ den.aspects.flat-aspect-test ];

        expr = igloo.networking.hostName;
        expected = "igloo";
      }
    );

  };
}
