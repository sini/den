{
  description = "Diagram demo: adapter-based excludes, substitutions, and Mermaid/DOT/PlantUML diagram rendering";

  outputs = inputs: inputs.flake-parts.lib.mkFlake { inherit inputs; } (inputs.import-tree ./modules);

  inputs = {
    den.url = "path:../..";
    import-tree.url = "github:vic/import-tree";
    flake-parts.url = "github:hercules-ci/flake-parts";
    flake-parts.inputs.nixpkgs-lib.follows = "nixpkgs";
    files.url = "github:mightyiam/files";
    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
    nixpkgs.url = "https://channels.nixos.org/nixpkgs-unstable/nixexprs.tar.xz";

    # External den flakes to trace
    gwenodai.url = "github:Gwenodai/nixos";
    gwenodai.inputs = {
      den.follows = "den";
      nixpkgs.follows = "nixpkgs";
      flake-parts.follows = "flake-parts";
      import-tree.follows = "import-tree";
      home-manager.follows = "home-manager";
    };
    adda.url = "git+https://codeberg.org/Adda/nixos-config.git";
    adda.inputs = {
      den.follows = "den";
      nixpkgs.follows = "nixpkgs";
      flake-parts.follows = "flake-parts";
      import-tree.follows = "import-tree";
      home-manager.follows = "home-manager";
    };
    quasigod.url = "git+https://tangled.org/quasigod.xyz/nixconfig";
    quasigod.inputs = {
      den.follows = "den";
      nixpkgs.follows = "nixpkgs";
      flake-parts.follows = "flake-parts";
      import-tree.follows = "import-tree";
      home-manager.follows = "home-manager";
    };
    drupol.url = "github:drupol/infra/push-woqtkxkpstro";
    drupol.inputs = {
      den.follows = "den";
      nixpkgs.follows = "nixpkgs";
      flake-parts.follows = "flake-parts";
      import-tree.follows = "import-tree";
      home-manager.follows = "home-manager";
    };
    flake-file.url = "github:vic/flake-file";
  };
}
