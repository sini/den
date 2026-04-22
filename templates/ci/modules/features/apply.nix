{ denTest, ... }:
{
  flake.tests.ctx.test-apply = denTest (
    { den, funnyNames, ... }:
    {
      den.ctx.foobar.description = "{foo,bar} context";
      den.ctx.foobar.provides.foobar =
        { foo, bar }:
        {
          funny.names = [
            foo
            bar
          ];
        };

      den.stages.foobar.funny.names = [ "owned" ];
      den.stages.foobar.includes = [ ];

      expr = funnyNames (
        den.ctx.foobar {
          foo = "moo";
          bar = "baa";
        }
      );

      expected = [
        "baa"
        "moo"
        "owned"
      ];
    }
  );
}
