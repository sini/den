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
