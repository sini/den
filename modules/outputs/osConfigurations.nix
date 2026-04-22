{ lib, den, ... }:
let
  ctx.flake-system.into.flake-os =
    { system }: map (host: { inherit host; }) (builtins.attrValues den.hosts.${system} or { });

  osFwd =
    { host }:
    den.provides.forward {
      each = lib.optional (host.intoAttr != [ ]) true;
      fromClass = _: host.class;
      intoClass = _: "flake";
      intoPath = _: [ "flake" ];
      fromAspect = _: den.lib.resolveStage "host" { inherit host; };
      mapModule =
        _: module:
        lib.setAttrByPath host.intoAttr (
          host.instantiate {
            modules = [
              module
              { nixpkgs.hostPlatform = lib.mkDefault host.system; }
            ];
          }
        );
    };
in
{
  den.ctx = ctx;
  den.stages.flake-system.provides.flake-os = _: osFwd;
}
