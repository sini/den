# modules/relationships/core.nix
#
# Core entity relationships — fundamental transitions between entity kinds.
# These parallel den.ctx.*.into declarations. Both coexist during migration;
# ctx-seen dedup prevents double resolution.
{ lib, ... }:
{
  den.relationships = {
    host-to-users = {
      from = "host";
      to = "user";
      resolve = { host }: map (user: { inherit host user; }) (lib.attrValues host.users);
    };
    host-to-default = {
      from = "host";
      to = "default";
      resolve = lib.singleton;
    };
    user-to-default = {
      from = "user";
      to = "default";
      resolve = lib.singleton;
    };
  };
}
