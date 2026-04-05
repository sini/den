{ den, ... }:
{
  den.aspects.server = {
    includes = with den.aspects; [
      networking
      monitoring
      monitoring._.node-exporter
      tailscale
      metrics-forward
    ];

    # Custom "metrics" class content, forwarded to nixos by metrics-forward
    metrics.scrape_configs = [
      {
        job_name = "node";
        static_configs = [ { targets = [ "localhost:9100" ]; } ];
      }
    ];
  };
}
