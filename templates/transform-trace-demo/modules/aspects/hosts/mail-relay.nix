{
  den,
  __findFile ? __findFile,
  ...
}:
let
  __findFile = den.lib.__findFile;
in
{
  den.hosts.x86_64-linux.mail-relay = {
    excludes = [ <monitoring> ];
    users.deploy = { };
  };
  den.aspects.mail-relay.includes = with den.aspects; [ relay ];
}
