{
  description = "Diagram demo: effects-based resolution pipeline with diagram rendering";

  outputs =
    inputs:
    inputs.flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [
        inputs.den.flakeModule
        # Load all modules with scopedImport so <aspect> syntax works
        # without per-file __findFile headers.
        (
          { den, ... }:
          {
            imports = [
              (inputs.import-tree.map (path:
                builtins.scopedImport {
                  inherit builtins;
                  __findFile = den.lib.__findFile;
                  __nixPath = [ ];
                } path
              ) ./modules)
            ];
          }
        )
      ];
    };

  inputs = {
    den.url = "path:../..";
    import-tree.url = "github:vic/import-tree";
    flake-parts.url = "github:hercules-ci/flake-parts";
    flake-parts.inputs.nixpkgs-lib.follows = "nixpkgs";
    files.url = "github:mightyiam/files";
    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
    nixpkgs.url = "https://channels.nixos.org/nixpkgs-unstable/nixexprs.tar.xz";
  };
}
