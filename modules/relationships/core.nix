# modules/relationships/core.nix
#
# Core entity relationships — fundamental transitions between entity kinds.
# These parallel den.ctx.*.into declarations. Both coexist during migration;
# existing into targets take priority (relationships add new targets only).
{ lib, ... }:
{
  den.relationships = {
    host-to-users = {
      from = "host";
      to = "user";
      resolve =
        ctx:
        if !(ctx ? host) || !(builtins.isAttrs ctx.host) || !(ctx.host ? users) then
          [ ]
        else
          map (user: {
            inherit (ctx) host;
            inherit user;
          }) (lib.attrValues ctx.host.users);
    };
    host-to-default = {
      from = "host";
      to = "default";
      resolve = ctx: if !(ctx ? host) || !(builtins.isAttrs ctx.host) then [ ] else [ ctx ];
    };
    user-to-default = {
      from = "user";
      to = "default";
      resolve = ctx: if !(ctx ? user) || !(builtins.isAttrs ctx.user) then [ ] else [ ctx ];
    };
  };
}
