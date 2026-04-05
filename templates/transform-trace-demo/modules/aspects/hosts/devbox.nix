{ den, ... }:
{
  den.hosts.x86_64-linux.devbox.users.alice = { };
  den.aspects.devbox = {
    excludes = with den.aspects; [ tailscale ];
    includes = with den.aspects; [
      workstation
      server
    ];
  };
}
