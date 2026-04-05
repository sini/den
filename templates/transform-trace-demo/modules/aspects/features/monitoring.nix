{ den, lib, ... }:
{
  den.aspects.monitoring = {
    nixos.services.prometheus.enable = true;

    provides.node-exporter.nixos.services.prometheus.exporters.node = {
      enable = true;
      enabledCollectors = [ "systemd" ];
    };

    provides.nginx-exporter.nixos.services.prometheus.exporters.nginx.enable = true;

    provides.alerting.nixos.services.prometheus.alertmanager.enable = true;
  };

  # Forward the "metrics" class from aspects into nixos
  den.aspects.metrics-forward =
    { class, aspect-chain }:
    den._.forward {
      each = lib.optional (class == "nixos") class;
      fromClass = _: "metrics";
      intoClass = _: "nixos";
      intoPath = _: [ ];
      fromAspect = _: lib.head aspect-chain;
    };
}
