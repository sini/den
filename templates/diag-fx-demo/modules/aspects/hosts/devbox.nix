{ den, ... }:
{
  den.aspects.devbox = {
    includes = with den.aspects; [
      workstation
      server
    ];
    # Compose two excludes: no tailscale, no docker (podman from workstation wins).
    meta.handleWith = [
      (den.lib.aspects.fx.constraints.exclude den.aspects.tailscale)
      (den.lib.aspects.fx.constraints.exclude den.aspects.virtualization._.docker)
    ];
  };
}
