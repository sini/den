# All resolve functions guard on expected context keys so they are safe
# to call from any pipeline context.
{ lib, ... }:
let
  host-has-user-with-class =
    host: class: builtins.any (user: lib.elem class user.classes) (lib.attrValues host.users);

  # Reusable detectHost — mirrors nix/lib/home-env.nix detectHost.
  mkDetectHost =
    {
      className,
      supportedOses ? [
        "nixos"
        "darwin"
      ],
      optionPath,
    }:
    ctx:
    if !(ctx ? host) || !(builtins.isAttrs ctx.host) then
      [ ]
    else
      let
        inherit (ctx) host;
        isOsSupported = builtins.elem host.class supportedOses;
        isEnabled = (host.${optionPath} or { }).enable or false;
        shouldActivate = isEnabled && isOsSupported && host-has-user-with-class host className;
      in
      lib.optional shouldActivate { inherit host; };

  # Reusable intoClassUsers — mirrors nix/lib/home-env.nix intoClassUsers.
  mkIntoClassUsers =
    className: ctx:
    if !(ctx ? host) || !(builtins.isAttrs ctx.host) || !(ctx.host ? users) then
      [ ]
    else
      map (user: {
        inherit (ctx) host;
        inherit user;
      }) (lib.filter (u: lib.elem className u.classes) (lib.attrValues ctx.host.users));

in
{
  den.policies = {
    # --- home-manager ---
    host-to-hm-host = {
      from = "host";
      to = "hm-host";
      resolve = mkDetectHost {
        className = "homeManager";
        optionPath = "home-manager";
      };
    };

    hm-host-to-hm-user = {
      from = "hm-host";
      to = "hm-user";
      resolve = mkIntoClassUsers "homeManager";
    };

    # --- hjem ---
    host-to-hjem-host = {
      from = "host";
      to = "hjem-host";
      resolve = mkDetectHost {
        className = "hjem";
        optionPath = "hjem";
      };
    };

    hjem-host-to-hjem-user = {
      from = "hjem-host";
      to = "hjem-user";
      resolve = mkIntoClassUsers "hjem";
    };

    # --- maid ---
    host-to-maid-host = {
      from = "host";
      to = "maid-host";
      resolve = mkDetectHost {
        className = "maid";
        supportedOses = [ "nixos" ];
        optionPath = "nix-maid";
      };
    };

    maid-host-to-maid-user = {
      from = "maid-host";
      to = "maid-user";
      resolve = mkIntoClassUsers "maid";
    };

    # --- WSL ---
    # WSL activation is host-config-driven (wsl.enable), not user-class-driven,
    # so it doesn't use mkDetectHost which requires matching user classes.
    host-to-wsl-host = {
      from = "host";
      to = "wsl-host";
      resolve =
        ctx:
        if !(ctx ? host) || !(builtins.isAttrs ctx.host) then
          [ ]
        else
          lib.optional (ctx.host.class or "" == "nixos" && (ctx.host.wsl or { }).enable or false) {
            inherit (ctx) host;
          };
    };

    # --- home-to-default ---
    home-to-default = {
      from = "home";
      to = "default";
      resolve = ctx: if !(ctx ? home) then [ ] else lib.singleton ctx;
    };
  };
}
