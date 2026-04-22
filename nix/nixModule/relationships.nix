# nix/nixModule/relationships.nix
{ den, lib, ... }:
let
  inherit (den.lib.relationshipTypes) relationshipType;
in
{
  options.den.relationships = lib.mkOption {
    description = "Relationship policies — declare how entity kinds relate.";
    default = { };
    defaultText = lib.literalExpression "{ }";
    type = lib.types.lazyAttrsOf relationshipType;
  };
}
