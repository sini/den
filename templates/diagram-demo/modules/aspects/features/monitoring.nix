# Monitoring stack with individually-addressable sub-providers.
#
# Sub-providers (provides.*) are separate aspects that can be excluded
# or filtered by constraint handlers. The server role includes all three
# unconditionally; hosts use meta.handleWith to prune unwanted exporters.
#
# See hosts/server.nix for exclude and filterBy patterns targeting these.
{ ... }:
{
  den.aspects.monitoring = {
    nixos.services.prometheus.enable = true;
    provides.node-exporter.nixos.services.prometheus.exporters.node = {
      enable = true;
      enabledCollectors = [ "systemd" ];
    };
    provides.nginx-exporter.nixos.services.prometheus.exporters.nginx.enable = true;
    provides.alerting.nixos.services.prometheus.alertmanager = {
      enable = true;
      configuration.route.receiver = "null";
      configuration.receivers = [ { name = "null"; } ];
    };
  };
}
