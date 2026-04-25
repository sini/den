{ den, ... }:
{
  den.aspects.dev-tools = {
    includes = [
      (den.provides.unfree [ "vscode" ])
    ];
    homeManager =
      { pkgs, ... }:
      {
        home.packages = with pkgs; [
          ripgrep
          fd
          jq
        ];
      };
  };
}
