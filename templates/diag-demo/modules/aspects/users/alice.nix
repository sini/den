{ den, ... }:
{
  den.aspects.alice = {
    includes = [
      den._.primary-user
      den.aspects.demo-shell
      den.aspects.hyprland
      den.aspects.dev-tools
    ];
    nixos = { ... }: { users.users.alice.isNormalUser = true; };
    homeManager = { pkgs, ... }: { home.packages = [ pkgs.git ]; };

    # Cross-provides: alice provides SSH config to every host she's on.
    provides.to-hosts.nixos.users.users.alice.openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAA... alice@example"
    ];
  };
}
