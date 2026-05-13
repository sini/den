# Core entity policies — fundamental traversal between entity kinds.
#
# host-to-users uses resolve.shared for shared fan-out.
# Entity-named nested keys on aspects (e.g., den.aspects.igloo.tux where
# tux is a user) are included in the target entity scope automatically.
# *-to-default policies eliminated — den.default is now injected as a
# schema include for host/user/home entity kinds (defaults.nix).
{ lib, den, ... }:
let
  inherit (den.lib.policy) resolve include;

  # Look up an entity-named nested key on an aspect, excluding keys
  # already handled by provides (forwarded via __providesForwarded).
  entityAspectChild =
    aspect: name:
    let
      forwarded = lib.genAttrs (aspect.__providesForwarded or [ ]) (_: true);
    in
    lib.optional (builtins.isAttrs aspect && aspect ? ${name} && !(forwarded ? ${name})) aspect.${name};
in
{
  # Host → users: fan-out to each declared user.
  # If the host aspect has a nested key matching the user name,
  # include it in the user scope (entity-named sub-aspect).
  den.policies.host-to-users =
    {
      host,
      ...
    }:
    lib.concatMap (
      user:
      [ (resolve.shared { inherit user; }) ] ++ map include (entityAspectChild host.aspect user.name)
    ) (lib.attrValues host.users);

  den.schema.host.includes = [ den.policies.host-to-users ];
}
