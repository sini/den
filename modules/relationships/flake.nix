# modules/relationships/flake.nix
#
# Flake output relationships — transitions from flake-level entity kinds.
#
# All resolve functions guard on expected context keys so they are safe to
# call from any pipeline context (the pipeline applies all relationships to
# every root aspect).
{
  den,
  lib,
  ...
}:
let
  systemOutputs = [
    "packages"
    "apps"
    "checks"
    "devShells"
    "legacyPackages"
  ];

  # A flake-system context has system but not entity-level keys. The existing
  # ctx into functions use strict { system } destructuring that rejects extra
  # attrs, so we must avoid firing when host/home are also present.
  isFlakeSystemCtx = ctx: ctx ? system && !(ctx ? host) && !(ctx ? home);

  systemOutputRels = map (output: {
    name = "flake-system-to-flake-${output}";
    value = {
      from = "flake-system";
      to = "flake-${output}";
      resolve =
        ctx:
        if isFlakeSystemCtx ctx then
          lib.singleton {
            inherit (ctx) system;
            output = output;
          }
        else
          [ ];
    };
  }) systemOutputs;
in
{
  den.relationships = lib.listToAttrs systemOutputRels // {
    flake-to-flake-system = {
      from = "flake";
      to = "flake-system";
      # Only fire from a pure flake context (no entity keys present).
      resolve =
        ctx:
        if !(ctx ? host) && !(ctx ? system) && !(ctx ? home) then
          map (system: { inherit system; }) den.systems
        else
          [ ];
    };

    flake-system-to-flake-os = {
      from = "flake-system";
      to = "flake-os";
      resolve =
        ctx:
        if isFlakeSystemCtx ctx then
          map (host: { inherit host; }) (builtins.attrValues den.hosts.${ctx.system} or { })
        else
          [ ];
    };

    flake-system-to-flake-hm = {
      from = "flake-system";
      to = "flake-hm";
      resolve =
        ctx:
        if isFlakeSystemCtx ctx then
          map (home: { inherit home; }) (builtins.attrValues den.homes.${ctx.system} or { })
        else
          [ ];
    };
  };
}
