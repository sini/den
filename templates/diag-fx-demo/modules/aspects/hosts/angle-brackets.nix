{ den, __findFile, ... }:
{
  den.aspects.angle-brackets = {
    includes = [
      <den/primary-user>
      den.aspects.networking
      den.aspects.tailscale
      den.aspects.desktop
    ];
    meta.handleWith = den.lib.aspects.fx.constraints.exclude den.aspects.tailscale;
  };
}
