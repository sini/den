{ den, ... }:
{
  den.hosts.x86_64-linux.desktop-gdm.users.alice = { };
  den.aspects.desktop-gdm = {
    transforms = [ (den.lib.aspects.transforms.substitute den.aspects.regreet den.aspects.gdm) ];
    includes = with den.aspects; [ workstation ];
  };
}
