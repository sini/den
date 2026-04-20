{ den, lib, ... }:
let
  description = ''
    Projects all `user.classes` like `homeManager` from the host's aspect tree
    onto users who opt in. Requires the fx pipeline.

    ## Usage

      den.aspects.tux.includes = [ den._.host-aspects ];

    Any host aspect that defines a `homeManager` key will have that
    config forwarded to the user's homeManager evaluation. Other host-class
    keys (nixos, darwin) are ignored — host.aspect is resolved
    specifically for `user.classes`.
  '';

  from-host =
    { host, user }:
    let
      # Tag host.aspect with user context so parametric includes like
      # { user }: ... can resolve during host-aspects re-resolution.
      ctx = { inherit host user; };
      aspectWithCtx = host.aspect // {
        __ctx = ctx;
        __scope = den.lib.fx.effects.scope.stateful (den.lib.aspects.fx.handlers.constantHandler ctx);
      };
    in
    lib.genAttrs (user.classes or [ "homeManager" ]) (
      class: den.lib.aspects.resolve class aspectWithCtx
    );
in
{
  den.provides.host-aspects = {
    inherit description;
    includes = [ from-host ];
  };
}
