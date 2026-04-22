{ denTest, lib, ... }:
{
  flake.tests.ctx-nested = {

    test-two-level-nesting = denTest (
      { den, funnyNames, ... }:
      {
        den.stages.ns.inner.provides.inner =
          { z }:
          {
            funny.names = [ "inner-${z}" ];
          };

        den.stages.root.provides.root =
          { v }:
          {
            funny.names = [ v ];
          };
        den.ctx.root.into =
          { v }:
          {
            ns.inner = [ { z = v; } ];
          };

        expr = funnyNames (den.lib.resolveStage "root" { v = "hello"; });
        expected = [
          "hello"
          "inner-hello"
        ];
      }
    );

    test-three-level-nesting = denTest (
      { den, funnyNames, ... }:
      {
        den.stages.a.b.c.provides.c =
          { z }:
          {
            funny.names = [ "abc-${z}" ];
          };

        den.ctx.start.into =
          { z }:
          {
            a.b.c = [ { z = z; } ];
          };

        expr = funnyNames (den.lib.resolveStage "start" { z = "deep"; });
        expected = [ "abc-deep" ];
      }
    );

    test-dedup-by-full-path = denTest (
      { den, funnyNames, ... }:
      {
        den.stages.a.leaf.provides.leaf =
          { v }:
          {
            funny.names = [ "a-${v}" ];
          };
        den.stages.b.leaf.provides.leaf =
          { v }:
          {
            funny.names = [ "b-${v}" ];
          };

        den.ctx.root.into = _: {
          a.leaf = [ { v = "x"; } ];
          b.leaf = [ { v = "y"; } ];
        };

        expr = funnyNames (den.lib.resolveStage "root" { });
        expected = [
          "a-x"
          "b-y"
        ];
      }
    );

    test-flat-still-works = denTest (
      { den, funnyNames, ... }:
      {
        den.stages.flat.provides.flat =
          { x }:
          {
            funny.names = [ x ];
          };

        den.relationships.test-root-to-flat = {
          from = "root";
          to = "flat";
          resolve = ctx: if !(builtins.isAttrs ctx) then [ ] else [ ctx ];
        };

        expr = funnyNames (den.lib.resolveStage "root" { x = "hi"; });
        expected = [ "hi" ];
      }
    );

    test-into-root-and-child-merge = denTest (
      { den, funnyNames, ... }:
      {
        den.stages.leaf.provides.leaf =
          { v }:
          {
            funny.names = [ v ];
          };

        imports = [
          {
            den.relationships.test-root-to-leaf-a = {
              from = "root";
              to = "leaf";
              resolve = _: [ { v = "a"; } ];
            };
          }

          {
            den.relationships.test-root-to-leaf-b = {
              from = "root";
              to = "leaf";
              resolve = _: [ { v = "b"; } ];
            };
          }

          {
            den.relationships.test-root-to-leaf-c = {
              from = "root";
              to = "leaf";
              resolve = _: [ { v = "c"; } ];
            };
          }

          {
            den.relationships.test-root-to-leaf-d = {
              from = "root";
              to = "leaf";
              resolve = _: [ { v = "d"; } ];
            };
          }
        ];

        expr = funnyNames (den.lib.resolveStage "root" { });
        expected = [
          "a"
          "b"
          "c"
          "d"
        ];
      }
    );

    test-into-mixed-flat-and-nested = denTest (
      { den, funnyNames, ... }:
      {
        den.stages.ns.deep.provides.deep =
          { k }:
          {
            funny.names = [ "deep-${k}" ];
          };
        den.stages.flat.provides.flat =
          { k }:
          {
            funny.names = [ "flat-${k}" ];
          };

        den.ctx.root.into =
          { k }:
          {
            flat = [ { inherit k; } ];
            ns.deep = [ { inherit k; } ];
          };

        expr = funnyNames (den.lib.resolveStage "root" { k = "v"; });
        expected = [
          "deep-v"
          "flat-v"
        ];
      }
    );
  };
}
