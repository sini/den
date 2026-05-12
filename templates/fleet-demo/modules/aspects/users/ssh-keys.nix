# ssh-keys: provision authorized SSH keys for users.
#
# Reads user.ssh-keys from the registry-sourced user entity and sets
# openssh.authorizedKeys.keys on the corresponding OS user.
# Only fires in user scope — keys land only on hosts where policies granted access.
{ ... }:
{
  den.aspects.ssh-keys = {
    nixos =
      { user, ... }:
      {
        users.users.${user.userName}.openssh.authorizedKeys.keys = user.ssh-keys;
      };
  };
}
