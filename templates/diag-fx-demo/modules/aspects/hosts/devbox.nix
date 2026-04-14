{ den, ... }:
{
  den.aspects.devbox = {
    includes = with den.aspects; [
      workstation
      server
    ];
    # Compose two excludes: no tailscale, no docker (podman from workstation wins).
    meta.adapter = [
      (den.lib.aspects.fx.excludeAspect den.aspects.tailscale)
      (den.lib.aspects.fx.excludeAspect den.aspects.virtualization._.docker)
    ];
  };
}
