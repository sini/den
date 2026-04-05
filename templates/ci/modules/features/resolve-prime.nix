{ denTest, ... }:
{
  flake.tests.resolve-prime = {

    # resolve' with no opts behaves like resolve
    test-resolve-prime-baseline = denTest (
      { den, funnyNamesWith, ... }:
      {
        den.ctx.src.description = "source";
        den.ctx.src._.src =
          { x }:
          {
            funny.names = [ x ];
          };

        expr = (funnyNamesWith { } (den.ctx.src { x = "hello"; })).names;
        expected = [ "hello" ];
      }
    );

    # resolve' with exclude transform filters aspects by name
    test-resolve-prime-exclude = denTest (
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
            funny.names = [ "keep" ];
            includes = [
              {
                name = "removeme";
                funny.names = [ "SHOULD-NOT-APPEAR" ];
              }
            ];
          };

        expr =
          (funnyNamesWith {
            transforms = [ (den.lib.aspects.transforms.exclude [ { name = "removeme"; } ]) ];
          } (den.ctx.src { x = "a"; })).names;
        expected = [ "keep" ];
      }
    );

    # resolve' with substitute transform swaps an aspect
    test-resolve-prime-substitute = denTest (
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
            funny.names = [ "base" ];
            includes = [
              {
                name = "original";
                funny.names = [ "ORIGINAL" ];
              }
            ];
          };

        expr =
          (funnyNamesWith {
            transforms = [
              (den.lib.aspects.transforms.substitute { name = "original"; } {
                name = "replacement";
                funny.names = [ "REPLACED" ];
              })
            ];
          } (den.ctx.src { x = "a"; })).names;
        expected = [
          "REPLACED"
          "base"
        ];
      }
    );

    # resolve' with trace = true returns trace entries
    test-resolve-prime-trace = denTest (
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
            funny.names = [ x ];
            includes = [
              {
                name = "child";
                funny.names = [ "from-child" ];
              }
            ];
          };

        expr =
          let
            r = funnyNamesWith { trace = true; } (den.ctx.src { x = "a"; });
            hasSrc = lib.any (t: t.name == "src" && t.decision == "included") r.trace;
            hasChild = lib.any (t: t.name == "child" && t.decision == "included") r.trace;
          in
          {
            names = r.names;
            hasTrace = r.trace != [ ];
            hasSrc = hasSrc;
            hasChild = hasChild;
          };
        expected = {
          names = [
            "a"
            "from-child"
          ];
          hasTrace = true;
          hasSrc = true;
          hasChild = true;
        };
      }
    );

    # resolve' trace shows pruned decision for excluded aspects
    test-resolve-prime-trace-pruned = denTest (
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
            funny.names = [ "keep" ];
            includes = [
              {
                name = "removed";
                funny.names = [ "GONE" ];
              }
            ];
          };

        expr =
          let
            r = funnyNamesWith {
              transforms = [ (den.lib.aspects.transforms.exclude [ { name = "removed"; } ]) ];
              trace = true;
            } (den.ctx.src { x = "a"; });
            named = builtins.filter (t: t.name != "<anon>" && t.name != "<function body>") r.trace;
            hasPruned = lib.any (t: t.name == "removed" && t.decision == "pruned") named;
          in
          {
            names = r.names;
            hasPruned = hasPruned;
          };
        expected = {
          names = [ "keep" ];
          hasPruned = true;
        };
      }
    );

    # resolve' trace shows replaced decision
    test-resolve-prime-trace-replaced = denTest (
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
            funny.names = [ "base" ];
            includes = [
              {
                name = "old";
                funny.names = [ "OLD" ];
              }
            ];
          };

        expr =
          let
            r = funnyNamesWith {
              transforms = [
                (den.lib.aspects.transforms.substitute { name = "old"; } {
                  name = "new";
                  funny.names = [ "NEW" ];
                })
              ];
              trace = true;
            } (den.ctx.src { x = "a"; });
            named = builtins.filter (t: t.name != "<anon>" && t.name != "<function body>") r.trace;
            hasReplaced = lib.any (t: t.name == "old" && t.decision == "replaced") named;
          in
          {
            names = r.names;
            hasReplaced = hasReplaced;
            hasTraceEntries = r.trace != [ ];
          };
        expected = {
          names = [
            "NEW"
            "base"
          ];
          hasReplaced = true;
          hasTraceEntries = true;
        };
      }
    );

    # compose multiple transforms
    test-resolve-prime-compose = denTest (
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
            funny.names = [ "base" ];
            includes = [
              {
                name = "a";
                funny.names = [ "A" ];
              }
              {
                name = "b";
                funny.names = [ "B" ];
              }
              {
                name = "c";
                funny.names = [ "C" ];
              }
            ];
          };

        expr =
          (funnyNamesWith {
            transforms = [
              (den.lib.aspects.transforms.exclude [ { name = "a"; } ])
              (den.lib.aspects.transforms.substitute { name = "b"; } {
                name = "b2";
                funny.names = [ "B2" ];
              })
            ];
          } (den.ctx.src { x = "val"; })).names;
        expected = [
          "B2"
          "C"
          "base"
        ];
      }
    );

    # resolve' trace includes provider field (list) for tagged aspects
    test-resolve-prime-provider-trace = denTest (
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
                name = "child";
                funny.names = [ "from-child" ];
                __provider = [ "parent-asp" ];
              }
            ];
          };

        expr =
          let
            r = funnyNamesWith { trace = true; } (den.ctx.src { x = "a"; });
            providerEntry = lib.findFirst (t: t.name == "child") null r.trace;
          in
          {
            hasProvider = providerEntry != null && providerEntry ? provider;
            providerValue = if providerEntry != null then providerEntry.provider or null else null;
          };
        expected = {
          hasProvider = true;
          providerValue = [ "parent-asp" ];
        };
      }
    );

    # resolve' trace shows pruned provider via cascade
    test-resolve-prime-provider-cascade = denTest (
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
                name = "monitoring";
                funny.names = [ "MON" ];
              }
              {
                name = "node-exporter";
                funny.names = [ "NEXPORTER" ];
                __provider = [ "monitoring" ];
              }
            ];
          };

        expr =
          let
            r = funnyNamesWith {
              transforms = [ (den.lib.aspects.transforms.exclude [ { name = "monitoring"; } ]) ];
              trace = true;
            } (den.ctx.src { x = "a"; });
            monEntry = lib.findFirst (t: t.name == "monitoring") null r.trace;
            nexEntry = lib.findFirst (t: t.name == "node-exporter") null r.trace;
          in
          {
            names = r.names;
            monPruned = monEntry != null && monEntry.decision == "pruned";
            nexPruned = nexEntry != null && nexEntry.decision == "pruned";
          };
        expected = {
          names = [ "root" ];
          monPruned = true;
          nexPruned = true;
        };
      }
    );

    # verify __provider set on real provides (list path)
    test-resolve-prime-real-provider-tag = denTest (
      { den, ... }:
      {
        den.aspects.base.provides.ext.funny.names = [ "EXT" ];
        expr = den.aspects.base._.ext.__provider;
        expected = [ "base" ];
      }
    );

    # __provider survives includes list and appears in trace
    test-resolve-prime-real-provider-in-includes = denTest (
      {
        den,
        lib,
        funnyNamesWith,
        ...
      }:
      {
        den.aspects.base.provides.ext.funny.names = [ "EXT" ];
        den.aspects.wrapper.includes = with den.aspects; [ base._.ext ];

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
          provider = [ "base" ];
        };
      }
    );

  };
}
