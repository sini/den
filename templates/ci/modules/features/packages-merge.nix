# Regression test for #572: multiple aspects defining `packages` should merge,
# not clobber (last-write-wins).
{ denTest, inputs, ... }:
{
  imports = [ inputs.den.flakeOutputs.packages ];

  flake.tests.packages-merge = {

    # Two aspects each defining a different package should both appear.
    test-multi-aspect-packages = denTest (
      {
        config,
        den,
        ...
      }:
      {
        imports = [ inputs.den.flakeOutputs.packages ];

        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.pkg-one.packages =
          { pkgs, ... }:
          {
            one = pkgs.writeText "one" "1";
          };

        den.aspects.pkg-two.packages =
          { pkgs, ... }:
          {
            two = pkgs.writeText "two" "2";
          };

        den.schema.flake-system.includes = [
          den.aspects.pkg-one
          den.aspects.pkg-two
        ];

        expr = builtins.sort (a: b: a < b) (builtins.attrNames config.flake.packages.x86_64-linux);
        expected = [
          "one"
          "two"
        ];
      }
    );

    # Same scenario using den.default includes.
    test-multi-aspect-packages-via-default = denTest (
      {
        config,
        den,
        ...
      }:
      {
        imports = [ inputs.den.flakeOutputs.packages ];

        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.default.includes = [
          den.aspects.pkg-alpha
          den.aspects.pkg-beta
        ];

        den.aspects.pkg-alpha.packages =
          { pkgs, ... }:
          {
            alpha = pkgs.writeText "alpha" "a";
          };

        den.aspects.pkg-beta.packages =
          { pkgs, ... }:
          {
            beta = pkgs.writeText "beta" "b";
          };

        expr = builtins.sort (a: b: a < b) (builtins.attrNames config.flake.packages.x86_64-linux);
        expected = [
          "alpha"
          "beta"
        ];
      }
    );

    # Overlapping key: last included aspect wins for same package name
    # (evalModules freeform merge with unspecified type).
    test-overlapping-key-last-wins = denTest (
      {
        config,
        den,
        ...
      }:
      {
        imports = [ inputs.den.flakeOutputs.packages ];

        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.pkg-v1.packages =
          { pkgs, ... }:
          {
            shared = pkgs.writeText "shared" "v1";
          };

        den.aspects.pkg-v2.packages =
          { pkgs, ... }:
          {
            shared = pkgs.writeText "shared" "v2";
          };

        den.schema.flake-system.includes = [
          den.aspects.pkg-v1
          den.aspects.pkg-v2
        ];

        # Both define "shared" — last included wins within the combined evalModules.
        expr = builtins.attrNames config.flake.packages.x86_64-linux;
        expected = [ "shared" ];
      }
    );

  };
}
