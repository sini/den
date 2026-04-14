{ den, __findFile, ... }:
{
  den.aspects.angle-brackets = {
    includes = [
      <den/primary-user>
      den.aspects.networking
      den.aspects.tailscale
      den.aspects.desktop
    ];
    meta.adapter = den.lib.aspects.fx.excludeAspect den.aspects.tailscale;
  };
}
