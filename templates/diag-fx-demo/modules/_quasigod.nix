# Import quasigod.xyz/nixconfig flake to trace their hosts.
{ inputs, ... }:
let
  import-tree = inputs.import-tree.matchNot ".*/den[.]nix|.*/default[.]nix|.*/vmvariant[.]nix|.*/formatter[.]nix";
in
{
  imports = [
    (inputs.den.namespace "styx" true)
    (import-tree (inputs.quasigod + "/modules"))
  ];
}
