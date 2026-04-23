# Core entity policies — fundamental traversal between entity kinds.
{ lib, ... }:
{
  den.policies = {
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
