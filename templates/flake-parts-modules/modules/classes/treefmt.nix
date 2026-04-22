{ inputs, ... }:
{
  imports = [ inputs.treefmt-nix.flakeModule ];
  den.relationships.flake-parts-to-flake-parts-system-treefmt = {
    from = "flake-parts";
    to = "flake-parts-system";
    resolve = _: [ { fromClass = _: "treefmt"; } ];
  };
}
