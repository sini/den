{ lib, ... }:
{
  den.schema.user.classes = lib.mkDefault [ "homeManager" ];

  den.hosts.x86_64-linux = {
    laptop.users.alice = { };
    server.users.deploy = { };
    devbox.users = {
      alice = { };
      bob = { };
    };
  };

  den.default.homeManager.home.stateVersion = "25.11";

  den.homes.x86_64-linux.alice = { };
}
