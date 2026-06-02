{ den, lib, ... }:
let
  description = ''
    Projects all `user.classes` like `homeManager` from the host's aspect tree
    onto users who opt in. Requires the fx pipeline.

    ## Usage

      den.aspects.tux.includes = [ den.batteries.host-aspects ];

    Any host aspect that defines a `homeManager` key will have that
    config forwarded to the user's homeManager evaluation. Other host-class
    keys (nixos, darwin) are ignored — host.aspect is resolved
    specifically for `user.classes`.
  '';

  # Emit a deferred node spawn request. Resolution happens post-walk (in
  # resolve.nix's drain augmentation) where the parent scope-tree state (host +
  # siblings) exists, so the projection sees the fleet — a host-aspects-projected
  # homeManager consumer of a fleet-collected pipe lists every peer. Ancestor
  # bindings like `environment` arrive via the threaded scope context, not
  # manual chainCtx threading.
  from-host =
    { host, user, ... }: [ (den.lib.policy.spawn { classes = user.classes or [ "homeManager" ]; }) ];
in
{
  den.batteries.host-aspects = {
    name = "host-aspects";
    inherit description;
    includes = [
      {
        __isPolicy = true;
        name = "host-aspects-project";
        fn = from-host;
      }
    ];
  };
}
