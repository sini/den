{ inputs, ... }:
{
  imports = [ inputs.files.flakeModules.default ];
  den.relationships.flake-parts-to-flake-parts-system-files = {
    from = "flake-parts";
    to = "flake-parts-system";
    resolve = _: [ { fromClass = _: "files"; } ];
  };
}
