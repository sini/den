# Devbox host: dual-role hybrid with multi-user support.
#
# Demonstrates five patterns:
#   1. <aspect> — angle-bracket references (via scopedImport, no header needed)
#   2. Dual role — workstation + server on one host
#   3. exclude — remove tailscale and docker (podman from workstation wins)
#   4. substitute — swap regreet greeter for gdm
#   5. Multi-user — alice (hyprland) + bob (gnome) on same host
{ den, ... }:
{
  den.aspects.devbox = {
    includes = [
      <den/batteries/primary-user>
      <workstation>
      <server>
    ];
    meta.handleWith = [
      # No tailscale on devbox
      (den.lib.aspects.fx.constraints.exclude <tailscale>)
      # Prefer podman over docker (podman comes from workstation)
      (den.lib.aspects.fx.constraints.exclude <virtualization/docker>)
      # Use gdm instead of the default regreet greeter
      (den.lib.aspects.fx.constraints.substitute <regreet> <gdm>)
    ];
  };
}
