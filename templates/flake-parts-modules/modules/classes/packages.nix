{

  # A class for flake-parts' perSystem.packages
  # NOTE: this is different from Den's flake-packages class.
  den.policies.flake-parts-to-flake-parts-system-packages = {
    from = "flake-parts";
    to = "flake-parts-system";
    resolve = _: [ { fromClass = _: "packages"; } ];
  };
}
