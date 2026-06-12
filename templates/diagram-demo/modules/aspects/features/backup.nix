# Parametric aspect: backup configuration adapts to the host it runs on.
#
# A plain function receiving { host } from the pipeline context. The host
# entity is bound at the host scope by handler-based resolution — this aspect
# consumes it to derive per-host paths.
{ den, ... }:
{
  den.aspects.backup =
    { host, ... }:
    {
      nixos.services.restic.backups.system = {
        repository = "s3:backup.example.com/${host.hostName}";
        passwordFile = "/dev/null";
        timerConfig.OnCalendar = "daily";
        paths = [
          "/etc"
          "/home"
        ];
      };
    };
}
