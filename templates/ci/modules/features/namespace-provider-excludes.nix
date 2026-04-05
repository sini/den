{ denTest, inputs, ... }:
{
  flake.tests.namespace-provider-excludes = {

    # Namespace providers get __provider qualified with namespace prefix
    test-namespace-provider-tag = denTest (
      { den, ns, ... }:
      {
        imports = [ (inputs.den.namespace "ns" false) ];
        ns.monitoring.provides.node-exporter.nixos.truth = true;

        expr = ns.monitoring._.node-exporter.__provider;
        expected = [
          "ns"
          "monitoring"
        ];
      }
    );

    # Namespace aspect itself gets __provider = [namespace]
    test-namespace-aspect-provider = denTest (
      {
        den,
        ns,
        igloo,
        ...
      }:
      {
        imports = [ (inputs.den.namespace "ns" false) ];
        den.hosts.x86_64-linux.igloo.users.tux = { };
        ns.gear.nixos.services.openssh.enable = true;
        den.aspects.igloo.includes = [ ns.gear ];

        expr = igloo.services.openssh.enable;
        expected = true;
      }
    );

    # Excluding a namespace aspect by ref does not affect same-named root aspect
    test-exclude-does-not-cross-namespace = denTest (
      {
        den,
        lib,
        ns,
        funnyNamesWith,
        ...
      }:
      {
        imports = [ (inputs.den.namespace "ns" false) ];

        den.ctx.src.description = "source";
        den.ctx.src._.src =
          { x }:
          {
            funny.names = [ "root" ];
            includes = [
              {
                name = "monitoring";
                funny.names = [ "ROOT-MON" ];
              }
              ns.monitoring
            ];
          };

        ns.monitoring.funny.names = [ "NS-MON" ];

        # Exclude only the namespace monitoring (path = ["ns" "monitoring"])
        # Root "monitoring" (path = ["monitoring"]) should survive
        expr =
          (funnyNamesWith {
            transforms = [ (den.lib.aspects.transforms.exclude [ ns.monitoring ]) ];
          } (den.ctx.src { x = "a"; })).names;
        expected = [
          "ROOT-MON"
          "root"
        ];
      }
    );

    # Excluding a namespace provider cascades within that namespace
    test-namespace-provider-cascade = denTest (
      {
        den,
        ns,
        igloo,
        ...
      }:
      {
        imports = [ (inputs.den.namespace "ns" false) ];
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.default.includes = [ den._.hostname ];

        ns.monitoring.nixos.services.prometheus.enable = true;
        ns.monitoring.provides.node-exporter.nixos.services.openssh.enable = true;

        den.aspects.server.includes = with ns; [
          monitoring
          monitoring._.node-exporter
        ];

        den.aspects.igloo = {
          excludes = [ ns.monitoring ];
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

    # Deep namespace providers get full chain via providerPrefix threading
    test-namespace-deep-provider-path = denTest (
      { den, ns, ... }:
      {
        imports = [ (inputs.den.namespace "ns" false) ];
        ns.monitoring.provides.node-exporter.provides.collector.nixos.truth = true;

        expr = {
          nodeExporter = ns.monitoring._.node-exporter.__provider;
          collector = ns.monitoring._.node-exporter._.collector.__provider;
        };
        expected = {
          nodeExporter = [
            "ns"
            "monitoring"
          ];
          collector = [
            "ns"
            "monitoring"
            "node-exporter"
          ];
        };
      }
    );

    # Namespace provider trace shows qualified path
    test-namespace-provider-trace = denTest (
      {
        den,
        lib,
        ns,
        funnyNamesWith,
        ...
      }:
      {
        imports = [ (inputs.den.namespace "ns" false) ];

        den.ctx.src.description = "source";
        den.ctx.src._.src =
          { x }:
          {
            funny.names = [ "root" ];
          };

        ns.base.provides.ext.funny.names = [ "EXT" ];
        den.aspects.wrapper.includes = [ ns.base._.ext ];

        expr =
          let
            r = funnyNamesWith { trace = true; } den.aspects.wrapper;
            extEntry = lib.findFirst (t: t.name == "ext") null r.trace;
          in
          {
            names = r.names;
            hasProvider = extEntry != null && extEntry ? provider;
            provider = if extEntry != null then extEntry.provider or "MISSING" else "NO ENTRY";
          };
        expected = {
          names = [ "EXT" ];
          hasProvider = true;
          provider = [
            "ns"
            "base"
          ];
        };
      }
    );

  };
}
