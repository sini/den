# Bug: direct nested sub-aspects auto-walk even when includes explicitly scopes
# which sub-aspects should be active.  With provides, forwarded keys are excluded
# from classification (via __providesForwarded).  Direct nesting should behave
# the same: when includes references own nested sub-keys, suppress auto-walk.
{
  denTest,
  lib,
  ...
}:
{
  flake.tests.deadbugs.nested-includes-scoping = {

    # includes references den.aspects.root.a -> only a should be walked, not b
    test-nested-includes-scoping = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.igloo.includes = [ den.aspects.root ];

        den.aspects.root = {
          includes = [ den.aspects.root.a ];

          a.nixos.environment.variables.FROM_A = "yes";
          b.nixos.environment.variables.FROM_B = "yes";
        };

        expr = {
          hasA = igloo.environment.variables ? FROM_A;
          hasB = igloo.environment.variables ? FROM_B;
        };
        expected = {
          hasA = true;
          hasB = false;
        };
      }
    );

    # Verify provides equivalent still works
    test-provides-includes-scoping = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.igloo.includes = [ den.aspects.root ];

        den.aspects.root = {
          includes = [ den.aspects.root.a ];

          provides.a.nixos.environment.variables.FROM_A = "yes";
          provides.b.nixos.environment.variables.FROM_B = "yes";
        };

        expr = {
          hasA = igloo.environment.variables ? FROM_A;
          hasB = igloo.environment.variables ? FROM_B;
        };
        expected = {
          hasA = true;
          hasB = false;
        };
      }
    );

    # No includes -> all nested keys auto-walk as before
    test-nested-auto-walk-no-includes = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.igloo.includes = [ den.aspects.root ];

        den.aspects.root = {
          a.nixos.environment.variables.FROM_A = "yes";
          b.nixos.environment.variables.FROM_B = "yes";
        };

        expr = {
          hasA = igloo.environment.variables ? FROM_A;
          hasB = igloo.environment.variables ? FROM_B;
        };
        expected = {
          hasA = true;
          hasB = true;
        };
      }
    );

    # includes with only external refs -> nested keys still auto-walk
    test-nested-auto-walk-external-includes = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.igloo.includes = [ den.aspects.root ];

        den.aspects.ext.nixos.environment.variables.FROM_EXT = "yes";

        den.aspects.root = {
          includes = [ den.aspects.ext ];

          a.nixos.environment.variables.FROM_A = "yes";
          b.nixos.environment.variables.FROM_B = "yes";
        };

        expr = {
          hasA = igloo.environment.variables ? FROM_A;
          hasB = igloo.environment.variables ? FROM_B;
          hasExt = igloo.environment.variables ? FROM_EXT;
        };
        expected = {
          hasA = true;
          hasB = true;
          hasExt = true;
        };
      }
    );
  };
}
