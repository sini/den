{ den, lib, ... }:
{
  den.default = {
    nixos.system.stateVersion = "25.11";
    includes = [
      den._.hostname
      den._.define-user
    ];

    # Stub boot config so NixOS evaluation doesn't fail
    nixos.boot.loader.grub.enable = false;
    nixos.fileSystems."/".device = "/dev/null";
  };
}
