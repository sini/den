{ lib, den, ... }:
{
  # findFile wiring for angle-bracket aspect references. Required by
  # `modules/aspects/hosts/angle-brackets.nix` and by any other file
  # that uses `<den/primary-user>` sugar. External flake imports
  # (gwenodai, drupol, ...) each set findFile in their own module
  # scope when enabled, which is independent from ours here.
  _module.args.__findFile = den.lib.__findFile;

  den.schema.user.classes = lib.mkDefault [ "homeManager" ];

  den.hosts.x86_64-linux = {
    laptop.users.alice = { };
    desktop-gdm.users.alice = { };
    web-server.users.deploy = { };
    mail-relay.users.deploy = { };
    devbox.users.alice = { };
    provider-filter.users.deploy = { };
    angle-brackets.users.alice = { };
    multi-desktop.users = {
      alice = { };
      bob = { };
    };
  };

  den.default.homeManager.home.stateVersion = "25.11";

  den.homes.x86_64-linux = {
    alice = { };
    "alice@laptop" = { };
  };
}
