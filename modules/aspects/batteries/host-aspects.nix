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

  # Resolution-chain entity bindings (e.g. a parent `environment`) carried in
  # the ambient context.  Threaded into the re-resolution below so the host
  # aspect tree binds the same ancestor args it bound at the host scope.
  entityKindAttrs = lib.genAttrs den.lib.schemaUtil.schemaEntityKinds (_: null);

  # Re-resolve the host's aspect tree for a user's classes, projecting host
  # class content (e.g. homeManager) onto the user.  A policy (not a bare
  # parametric include) so it receives the full ambient resolveCtx — the host
  # scope is a descendant of its parent entities (e.g. `environment`), and that
  # ancestor context must survive into the re-resolution.  Without it,
  # parametric host aspects re-fired here (e.g. a quirk emit `{ environment,
  # host, ... }: ...`) would be stranded unresolved.
  from-host =
    { host, user, ... }@ctx:
    let
      chainCtx = builtins.intersectAttrs entityKindAttrs ctx // {
        inherit host user;
      };
      scopeHandlers = den.lib.aspects.fx.handlers.constantHandler chainCtx;
      aspectWithCtx = host.aspect // {
        __scopeHandlers = scopeHandlers;
      };
      projected = {
        name = "host-aspects/${user.userName}@${host.name}";
      }
      // lib.genAttrs (user.classes or [ "homeManager" ]) (
        class: den.lib.aspects.resolveImports class aspectWithCtx
      );
    in
    [ (den.lib.policy.include projected) ];
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
