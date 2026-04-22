{ denTest, lib, ... }:
{
  flake.tests.ctx-nested-providers = {

    # Cross-providers for nested ctx should use the FULL PATH, not local name.
    # root.provides.ns.inner targets ctx at den.ctx.ns.inner specifically.
    test-nested-cross-provider = denTest (
      { den, funnyNames, ... }:
      {
        den.stages.ns.inner.provides.inner =
          { z }:
          {
            funny.names = [ "inner-${z}" ];
          };

        den.ctx.root.into =
          { z }:
          {
            ns.inner = [ { inherit z; } ];
          };

        den.stages.root.provides.${"ns.inner"} =
          _:
          { z }:
          {
            funny.names = [ "root-for-inner-${z}" ];
          };

        expr = funnyNames (den.lib.resolveStage "root" { z = "x"; });
        expected = [
          "inner-x"
          "root-for-inner-x"
        ];
      }
    );

    # Two nested contexts with the same local name must get independent cross-providers.
    test-no-cross-provider-collision = denTest (
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

        den.stages.root.provides.${"a.leaf"} =
          _:
          { v }:
          {
            funny.names = [ "cross-a-${v}" ];
          };

        expr = funnyNames (den.lib.resolveStage "root" { });
        expected = [
          "a-x"
          "b-y"
          "cross-a-x"
        ];
      }
    );

    # Attrset-form into with nested keys: into.ns.inner = fn
    test-nested-attrset-into = denTest (
      { den, funnyNames, ... }:
      {
        den.stages.ns.inner.provides.inner =
          { z }:
          {
            funny.names = [ "inner-${z}" ];
          };

        den.ctx.root.into.ns.inner = lib.singleton;

        expr = funnyNames (den.lib.resolveStage "root" { z = "q"; });
        expected = [ "inner-q" ];
      }
    );
  };
}
