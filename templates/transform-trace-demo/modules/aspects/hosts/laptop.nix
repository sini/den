{ den, ... }:
{
  den.hosts.x86_64-linux.laptop.users.alice = { };
  den.aspects.laptop.includes = with den.aspects; [ workstation ];
}
