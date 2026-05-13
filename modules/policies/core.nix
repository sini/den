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
in
{
  # Host → users: fan-out to each declared user.
  # If the host aspect has a freeform key matching the user name
  # (not from provides — those are handled by mkCrossPolicy),
  # include it in the user scope as an entity-named sub-aspect.
  den.policies.host-to-users =
    {
      host,
      ...
    }:
    let
      aspect = host.aspect;
      forwarded = lib.genAttrs (aspect.__providesForwarded or [ ]) (_: true);
      hasChild = name: builtins.isAttrs aspect && aspect ? ${name} && !(forwarded ? ${name});
    in
    lib.concatMap (
      user:
      [ (resolve.shared { inherit user; }) ]
      ++ lib.optional (hasChild user.name) (include aspect.${user.name})
    ) (lib.attrValues host.users);

  den.schema.host.includes = [ den.policies.host-to-users ];
}
