{ den, ... }:
{
  den.aspects.hyprland = {
    includes = [
      (den.provides.unfree [
        "nvidia-x11"
        "nvidia-settings"
      ])
    ];
    nixos.programs.hyprland.enable = true;
    homeManager.wayland.windowManager.hyprland.enable = true;
  };
}
