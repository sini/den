# Import Adda/nixos-config flake to trace their hosts.
{ inputs, ... }:
let
  import-tree = inputs.import-tree.matchNot ".*/den[.]nix|.*/defaults[.]nix|.*/namespaces[.]nix|.*/vm[.]nix|.*/tests[.]nix|.*/devshells/.*|.*/flake/.*|.*/files/.*";
in
{
  imports = [
    (inputs.den.namespace "addax" false)
    (import-tree (inputs.adda + "/modules"))
  ];
}
