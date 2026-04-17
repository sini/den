{ den, ... }:
{
  den.aspects.devbox = {
    includes = with den.aspects; [
      workstation
      server
    ];
    # Compose two excludes: no tailscale, no docker (podman from workstation wins).
    meta.adapter = inherited:
      let inherit (den.lib.aspects.adapters) excludeAspect;
      in excludeAspect den.aspects.tailscale (
        excludeAspect den.aspects.virtualization._.docker inherited
      );
  };
}
