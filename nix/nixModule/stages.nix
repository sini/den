{ den, lib, ... }:
let
  inherit (den.lib.stageTypes) stageTreeType;
in
{
  options.den.stages = lib.mkOption {
    description = "Named scopes for binding behavior to pipeline stages.";
    default = { };
    defaultText = lib.literalExpression "{ }";
    type = lib.types.lazyAttrsOf stageTreeType;
  };
}
