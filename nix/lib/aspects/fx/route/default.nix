# Route module delivery — move modules between entity scopes/classes.
{
  lib,
  den,
  ...
}:
let
  inherit (import ./wrap.nix { inherit lib den; }) collectClassMods;
  inherit
    (import ./apply.nix {
      inherit lib den collectClassMods;
    })
    applyRoutes
    ;
in
{
  inherit applyRoutes;
}
