{ inputs, ... }:
{
  imports = [ inputs.treefmt-nix.flakeModule ];
  den.policies.flake-parts-to-flake-parts-system-treefmt = {
    from = "flake-parts";
    to = "flake-parts-system";
    resolve = _: [ { fromClass = _: "treefmt"; } ];
  };
}
