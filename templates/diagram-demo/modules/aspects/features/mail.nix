# Parametric aspect: mail relay configured per-host.
# den.lib.perHost provides { host } from the pipeline context.
{ den, ... }:
{
  den.aspects.mail = den.lib.perHost (
    { host }:
    {
      nixos.services.postfix = {
        enable = true;
        hostname = host.hostName;
      };
    }
  );
}
