# Parametric aspect: mail relay configured per-host.
# A plain function receiving { host } from the pipeline context; bound at the
# host scope by handler-based resolution.
{ den, ... }:
{
  den.aspects.mail =
    { host, ... }:
    {
      nixos.services.postfix = {
        enable = true;
        hostname = host.hostName;
      };
    };
}
