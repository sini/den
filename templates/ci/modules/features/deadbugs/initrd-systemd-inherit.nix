# Regression: boot.initrd.systemd = { inherit (config.systemd) network; services.x.preStart = ...; }
# When two aspects both contribute to boot.initrd.systemd and one uses
# inherit (config.systemd) network, the sibling services key gets dropped.
# Uses real nixosConfigurations to reproduce the cross-module merge issue.
{ denTest, ... }:
{
  flake.tests.initrd-systemd-inherit = {
    test-prestart-survives-inherit-across-aspects = denTest (
      { den, config, ... }:
      let
        iglooConfig = config.flake.nixosConfigurations.igloo.config;
      in
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.igloo = {
          includes = [
            den.aspects.net-boot
            den.aspects.rollback
          ];
        };

        # Aspect 1: sets up network + ZFS + copies network config to initrd
        den.aspects.net-boot = {
          nixos =
            { config, pkgs, ... }:
            {
              boot.supportedFilesystems.zfs = true;
              boot.zfs.devNodes = "/dev/disk/by-id/";
              boot.initrd.systemd.enable = true;

              systemd.network.enable = true;
              systemd.network.networks."10-test" = {
                matchConfig.Name = "eth0";
                networkConfig.DHCP = "yes";
              };

              boot.initrd.systemd = {
                inherit (config.systemd) network;
                services.zfs-import-zroot.preStart = "echo pre";
              };
            };
        };

        # Aspect 2: another initrd service (like impermanence rollback)
        den.aspects.rollback = {
          nixos = {
            boot.initrd.systemd.services.rollback = {
              description = "rollback";
              wantedBy = [ "initrd.target" ];
              serviceConfig.Type = "oneshot";
              script = "echo rollback";
            };
          };
        };

        expr = {
          preStart = iglooConfig.boot.initrd.systemd.services.zfs-import-zroot.preStart;
          rollbackScript = iglooConfig.boot.initrd.systemd.services.rollback.script;
        };
        expected = {
          preStart = "echo pre";
          rollbackScript = "echo rollback";
        };
      }
    );
  };
}
