# Angle brackets work in excludes (circular eval fixed by trace refactor).
# Slash notation resolves providers: <monitoring/alerting> = monitoring.provides.alerting
{
  den,
  __findFile ? __findFile,
  ...
}:
let
  __findFile = den.lib.__findFile;
in
{
  den.hosts.x86_64-linux.angle-brackets-demo.users.alice = { };
  den.aspects.angle-brackets-demo = {
    excludes = [ <tailscale> ];
    transforms = [ (den.lib.aspects.transforms.substitute <regreet> den.aspects.gdm) ];
    includes = [
      <workstation>
      <server>
    ];
  };
}
