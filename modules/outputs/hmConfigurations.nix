{ lib, den, ... }:
let
  hmFwd =
    { home }:
    den.provides.forward {
      each = lib.optional (home.intoAttr != [ ]) true;
      fromClass = _: home.class;
      intoClass = _: "flake";
      intoPath = _: [ "flake" ];
      fromAspect = _: den.lib.resolveStage "home" { inherit home; };
      mapModule =
        _: module:
        lib.setAttrByPath home.intoAttr (
          home.instantiate {
            pkgs = home.pkgs;
            modules = [ module ];
          }
        );
    };
in
{
  den.stages.flake-system.provides.flake-hm = _: hmFwd;
}
