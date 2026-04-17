{ den, ... }:
{
  # Parametric backup — adapts to the host it runs on.
  den.aspects.backup = den.lib.perHost (
    { host }:
    {
      nixos.services.restic.backups.system = {
        repository = "s3:backup.example.com/${host.hostName}";
        passwordFile = "/dev/null";
        timerConfig.OnCalendar = "daily";
        paths = [ "/etc" "/home" ];
      };
    }
  );
}
