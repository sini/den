# Import Gwenodai/nixos flake to trace their hosts.
{ inputs, den, ... }:
let
  import-tree = inputs.import-tree.matchNot ".*/core/(den|flake-lib|defaults)[.]nix|.*/vm[.]nix|.*/tests[.]nix";
in
{
  imports = [
    (inputs.flake-file.flakeModules.dendritic or { })
    (import-tree (inputs.gwenodai + "/modules"))
  ];
  _module.args.__findFile = den.lib.__findFile;

}
