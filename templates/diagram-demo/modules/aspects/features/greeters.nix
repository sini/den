# Display manager aspects — mutually exclusive via constraint substitution.
# See hosts/devbox.nix for substitute pattern: regreet → gdm.
{ ... }:
{
  den.aspects = {
    regreet.nixos.programs.regreet.enable = true;
    gdm.nixos.services.xserver.displayManager.gdm.enable = true;
    sddm.nixos.services.displayManager.sddm.enable = true;
  };
}
