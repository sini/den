{ denTest, ... }:
{
  flake.tests.false-positive = {
    # External include shares leaf name with current aspect
    test-cross-aspect-name-collision = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.aspects.igloo.includes = [ den.aspects.root ];

        # den.aspects.other.root.a — an external sub-aspect
        den.aspects.other.root.a.nixos.environment.variables.FROM_OTHER = "yes";

        # den.aspects.root has nested key "a" AND includes an external
        # sub-aspect that happens to share the leaf name "root"
        den.aspects.root = {
          includes = [ den.aspects.other.root.a ];
          a.nixos.environment.variables.FROM_A = "yes";
          b.nixos.environment.variables.FROM_B = "yes";
        };

        expr = {
          hasA = igloo.environment.variables ? FROM_A;
          hasB = igloo.environment.variables ? FROM_B;
          hasOther = igloo.environment.variables ? FROM_OTHER;
        };
        # All three should be present: a and b auto-walk,
        # other.root.a is an external include
        expected = {
          hasA = true;
          hasB = true;
          hasOther = true;
        };
      }
    );
  };
}
