{ den, ... }:
{
  den.hosts.x86_64-linux.web-server.users.deploy = { };
  den.aspects.web-server.includes = with den.aspects; [
    server
    monitoring._.nginx-exporter
    monitoring._.alerting
  ];
}
