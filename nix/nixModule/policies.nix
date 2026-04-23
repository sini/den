{ den, lib, ... }:
let
  inherit (den.lib.policyTypes) policyType;
in
{
  options.den.policies = lib.mkOption {
    description = "Policies — declare directed edges between entity kinds with computed adjacency.";
    default = { };
    defaultText = lib.literalExpression "{ }";
    type = lib.types.lazyAttrsOf policyType;
  };
}
