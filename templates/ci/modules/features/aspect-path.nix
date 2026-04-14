{ denTest, lib, ... }:
{
  flake.tests.aspect-path = {

    test-aspectPath-named = denTest (
      { den, ... }:
      {
        den.aspects.foo.nixos = { };
        expr = den.lib.aspects.adapters.aspectPath den.aspects.foo;
        expected = [ "foo" ];
      }
    );

    test-aspectPath-with-provider = denTest (
      { den, ... }:
      {
        den.aspects.monitoring = {
          nixos = { };
          provides.node-exporter.nixos = { };
        };
        expr = den.lib.aspects.adapters.aspectPath den.aspects.monitoring._.node-exporter;
        expected = [
          "monitoring"
          "node-exporter"
        ];
      }
    );

    # excludeAspect: excluded include becomes a tombstone (visible in trace)
    test-excludeAspect-tombstone-in-trace = denTest (
      { den, trace, ... }:
      {
        den.aspects.foo.includes = [
          den.aspects.bar
          den.aspects.baz
        ];
        den.aspects.foo.meta.adapter =
          inherited: den.lib.aspects.adapters.excludeAspect den.aspects.baz inherited;
        den.aspects.bar.nixos = { };
        den.aspects.baz.nixos = { };

        expr = trace "nixos" den.aspects.foo;
        # baz appears as tombstone (~baz, no children)
        expected.trace = [
          "foo"
          [ "bar" ]
          [ "~baz" ]
        ];
      }
    );

    # excludeAspect: tombstone contributes no modules to the build
    test-excludeAspect-no-modules = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo = { };
        den.aspects.igloo.includes = [
          den.aspects.bar
          den.aspects.baz
        ];
        den.aspects.igloo.meta.adapter =
          inherited: den.lib.aspects.adapters.excludeAspect den.aspects.baz inherited;
        den.aspects.bar.nixos.environment.sessionVariables.msg = "bar";
        den.aspects.baz.nixos.environment.sessionVariables.msg = "baz";

        # only bar's module is included, baz is excluded
        expr = igloo.environment.sessionVariables.msg;
        expected = "bar";
      }
    );

    # excludeAspect: propagates through subtree
    test-excludeAspect-propagates-to-subtree = denTest (
      { den, trace, ... }:
      {
        den.aspects.root.includes = [ den.aspects.role ];
        den.aspects.root.meta.adapter =
          inherited: den.lib.aspects.adapters.excludeAspect den.aspects.baz inherited;
        den.aspects.role.includes = [
          den.aspects.bar
          den.aspects.baz
        ];
        den.aspects.bar.nixos = { };
        den.aspects.baz.nixos = { };

        expr = trace "nixos" den.aspects.root;
        # baz tombstone appears in role's subtree
        expected.trace = [
          "root"
          [
            "role"
            [ "bar" ]
            [ "~baz" ]
          ]
        ];
      }
    );

    # excludeAspect: by provider path
    test-excludeAspect-by-provider = denTest (
      { den, trace, ... }:
      {
        den.aspects.monitoring = {
          nixos = { };
          provides.node-exporter.nixos = { };
          provides.alerting.nixos = { };
        };
        den.aspects.server.includes = with den.aspects; [
          monitoring
          monitoring._.node-exporter
          monitoring._.alerting
        ];
        den.aspects.server.meta.adapter =
          inherited: den.lib.aspects.adapters.excludeAspect den.aspects.monitoring._.node-exporter inherited;

        expr = trace "nixos" den.aspects.server;
        # node-exporter tombstone visible, alerting kept
        expected.trace = [
          "server"
          [ "monitoring" ]
          [ "~node-exporter" ]
          [ "alerting" ]
        ];
      }
    );

    # excludeAspect: excluding a parent also excludes its providers
    test-excludeAspect-cascades-to-providers = denTest (
      { den, trace, ... }:
      {
        den.aspects.monitoring = {
          nixos = { };
          provides.node-exporter.nixos = { };
          provides.alerting.nixos = { };
        };
        den.aspects.server.includes = with den.aspects; [
          monitoring
          monitoring._.node-exporter
          monitoring._.alerting
        ];
        den.aspects.server.meta.adapter =
          inherited: den.lib.aspects.adapters.excludeAspect den.aspects.monitoring inherited;

        expr = trace "nixos" den.aspects.server;
        # monitoring and all its providers excluded
        expected.trace = [
          "server"
          [ "~monitoring" ]
          [ "~node-exporter" ]
          [ "~alerting" ]
        ];
      }
    );

    # substituteAspect: replaced include becomes tombstone + replacement
    test-substituteAspect-replaces = denTest (
      { den, trace, ... }:
      {
        den.aspects.foo.includes = [
          den.aspects.bar
          den.aspects.baz
        ];
        den.aspects.foo.meta.adapter =
          inherited: den.lib.aspects.adapters.substituteAspect den.aspects.bar den.aspects.qux inherited;
        den.aspects.bar.nixos = { };
        den.aspects.baz.nixos = { };
        den.aspects.qux.nixos = { };

        expr = trace "nixos" den.aspects.foo;
        # bar tombstone + qux replacement, baz unchanged
        expected.trace = [
          "foo"
          [ "~bar" ]
          [ "qux" ]
          [ "baz" ]
        ];
      }
    );

    # substituteAspect: replacement modules are used in build
    test-substituteAspect-build-uses-replacement = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo = { };
        den.aspects.igloo.includes = [ den.aspects.bar ];
        den.aspects.igloo.meta.adapter =
          inherited: den.lib.aspects.adapters.substituteAspect den.aspects.bar den.aspects.qux inherited;
        den.aspects.bar.nixos.environment.sessionVariables.msg = "bar";
        den.aspects.qux.nixos.environment.sessionVariables.msg = "qux";

        # qux's module is used, not bar's
        expr = igloo.environment.sessionVariables.msg;
        expected = "qux";
      }
    );

    # substituteAspect: propagates through subtree
    test-substituteAspect-propagates = denTest (
      { den, trace, ... }:
      {
        den.aspects.root.includes = [ den.aspects.role ];
        den.aspects.root.meta.adapter =
          inherited: den.lib.aspects.adapters.substituteAspect den.aspects.baz den.aspects.qux inherited;
        den.aspects.role.includes = [
          den.aspects.bar
          den.aspects.baz
        ];
        den.aspects.bar.nixos = { };
        den.aspects.baz.nixos = { };
        den.aspects.qux.nixos = { };

        expr = trace "nixos" den.aspects.root;
        # baz tombstone + qux in role's subtree
        expected.trace = [
          "root"
          [
            "role"
            [ "bar" ]
            [ "~baz" ]
            [ "qux" ]
          ]
        ];
      }
    );

    # structuredTrace: produces entry objects with metadata
    test-structuredTrace-entries = denTest (
      { den, lib, ... }:
      {
        den.aspects.foo.includes = [ den.aspects.bar ];
        den.aspects.foo.meta.adapter =
          inherited: den.lib.aspects.adapters.excludeAspect den.aspects.bar inherited;
        den.aspects.bar.nixos = { };

        expr =
          let
            result =
              den.lib.aspects.resolve.withAdapter den.lib.aspects.adapters.structuredTrace "nixos"
                den.aspects.foo;
            entries = builtins.filter (
              e: e.name != "<anon>" && !(lib.hasPrefix "[definition " e.name)
            ) result.trace;
          in
          map (e: { inherit (e) name excluded; }) entries;
        expected = [
          {
            name = "foo";
            excluded = false;
          }
          {
            name = "bar";
            excluded = true;
          }
        ];
      }
    );

    # structuredTrace: excludedFrom reports the user-declared adapter
    # owner, not the anonymous wrapper that the adapter was tagged
    # onto. Regression test for the attribution-drift fix in
    # filterIncludes.
    test-structuredTrace-excludedFrom-attribution = denTest (
      { den, lib, ... }:
      {
        # host includes role, role includes target. host's adapter
        # excludes target — so the tombstone should say
        # excludedFrom = "host-aspect", not "<anon>" or "role".
        den.aspects.host-aspect = {
          includes = [ den.aspects.role ];
          meta.adapter = inherited: den.lib.aspects.adapters.excludeAspect den.aspects.target inherited;
        };
        den.aspects.role.includes = [
          den.aspects.target
          den.aspects.survivor
        ];
        den.aspects.target.nixos = { };
        den.aspects.survivor.nixos = { };

        expr =
          let
            result =
              den.lib.aspects.resolve.withAdapter den.lib.aspects.adapters.structuredTrace "nixos"
                den.aspects.host-aspect;
            entries = builtins.filter (
              e: e.name != "<anon>" && !(lib.hasPrefix "[definition " e.name)
            ) result.trace;
          in
          map (e: {
            inherit (e) name excluded;
            excludedFrom = e.excludedFrom or null;
          }) entries;
        expected = [
          {
            name = "host-aspect";
            excluded = false;
            excludedFrom = null;
          }
          {
            name = "role";
            excluded = false;
            excludedFrom = null;
          }
          {
            name = "target";
            excluded = true;
            excludedFrom = "host-aspect";
          }
          {
            name = "survivor";
            excluded = false;
            excludedFrom = null;
          }
        ];
      }
    );

    # structuredTrace: excludedFrom carries through multi-level
    # adapter propagation. outer's adapter tags onto middle, then
    # middle's filterIncludes tombstones victim. The tombstone should
    # report "outer" (the originating adapter owner), not "middle"
    # or "<anon>".
    test-structuredTrace-excludedFrom-propagation = denTest (
      { den, lib, ... }:
      {
        den.aspects.outer = {
          includes = [ den.aspects.middle ];
          meta.adapter = inherited: den.lib.aspects.adapters.excludeAspect den.aspects.victim inherited;
        };
        den.aspects.middle.includes = [
          den.aspects.victim
          den.aspects.keep
        ];
        den.aspects.victim.nixos = { };
        den.aspects.keep.nixos = { };

        expr =
          let
            result =
              den.lib.aspects.resolve.withAdapter den.lib.aspects.adapters.structuredTrace "nixos"
                den.aspects.outer;
            entries = builtins.filter (e: e.name == "victim") result.trace;
          in
          map (e: e.excludedFrom or null) entries;
        # Attribution stays with "outer" even though the tombstone
        # is created at the "middle" level.
        expected = [ "outer" ];
      }
    );

    # perHost parametric aspects should appear in trace by name
    test-perHost-visible-in-trace = denTest (
      { den, trace, ... }:
      {
        den.aspects.role.includes = with den.aspects; [
          leaf
          param
        ];
        den.aspects.leaf.nixos = { };
        den.aspects.param = den.lib.perHost (
          { host }:
          {
            nixos = { };
          }
        );

        expr = trace "nixos" den.aspects.role;
        expected.trace = [
          "role"
          [ "leaf" ]
          [
            "param"
            [ "[definition 1-entry 1]" ]
          ]
        ];
      }
    );

    # structuredTrace: ctxStage is set when resolved through den.ctx.host.
    # Check that key aspects get the right stage, ignoring duplicates.
    test-structuredTrace-ctxStage = denTest (
      { den, lib, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.aspects.igloo.nixos = { };
        den.aspects.tux.nixos = { };

        expr =
          let
            host = den.hosts.x86_64-linux.igloo;
            asp = den.ctx.host { inherit host; };
            result = den.lib.aspects.resolve.withAdapter den.lib.aspects.adapters.structuredTrace "nixos" asp;
            isInternal =
              n:
              lib.hasPrefix "<" n
              || lib.hasPrefix "[" n
              || builtins.match ".+/(aspect|self-provide|cross-provide|resolve).*" n != null;
            named = builtins.filter (e: !isInternal e.name) result.trace;
            # Deduplicate by name, take first occurrence.
            dedup =
              builtins.foldl'
                (
                  acc: e:
                  if acc.seen ? ${e.name} then
                    acc
                  else
                    {
                      seen = acc.seen // {
                        ${e.name} = true;
                      };
                      result = acc.result ++ [ e ];
                    }
                )
                {
                  seen = { };
                  result = [ ];
                }
                named;
          in
          map (e: {
            inherit (e) name;
            ctxStage = e.ctxStage or null;
          }) dedup.result;
        expected = [
          {
            name = "host";
            ctxStage = null;
          }
          {
            name = "igloo";
            ctxStage = "host";
          }
          {
            name = "default";
            ctxStage = "default";
          }
          {
            name = "hm-host";
            ctxStage = "hm-host";
          }
          {
            name = "hm-user";
            ctxStage = "hm-user";
          }
          {
            name = "user";
            ctxStage = "user";
          }
          {
            name = "tux";
            ctxStage = "user";
          }
        ];
      }
    );

  };
}
