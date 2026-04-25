# Parametric aspect: backup configuration adapts to the host it runs on.
#
# den.lib.perHost wraps a function that receives { host } from the
# pipeline context. The host entity is provided by the host-to-users
# policy chain — this aspect consumes it to derive per-host paths.
{ den, ... }:
{
  den.aspects.backup = den.lib.perHost (
    { host }:
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
    }
  );
}
