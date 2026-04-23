# nix/lib/relationship-types.nix
#
# Relationship type definitions. A relationship declares how one entity
# kind transitions to another — pure topology, no behavior.
{ lib, ... }:
let
  relationshipType = lib.types.submodule {
    options = {
      from = lib.mkOption {
        type = lib.types.str;
        description = "Source entity kind (e.g., 'host')";
      };
      to = lib.mkOption {
        type = lib.types.str;
        description = "Target entity kind or stage name (e.g., 'user', 'hm-host')";
      };
      resolve = lib.mkOption {
        type = lib.types.raw;
        description = ''
          Function that takes accumulated pipeline context and returns
          a list of target context attrsets.
          Example: { host }: map (user: { inherit host user; }) (lib.attrValues host.users)
        '';
      };
    };
  };
in
{
  inherit relationshipType;
}
