# Deprecated context-level guards.
# Under handler-based resolution, bind.fn resolves each arg independently.
# Optional args with no handler are skipped (nix-effects c7931d7), so
# the function body can detect context level by checking which keys
# were resolved.
{ lib, ... }:
let
  # Known context keys. Keys not in the required set are declared as
  # optional — if their handlers exist (deeper level), the function
  # detects the extras and returns {} (no-op).
  allContextKeys = [
    "host"
    "user"
    "home"
  ];

  perCtx =
    requiredKeys: aspect:
    let
      reqKeysSorted = builtins.sort builtins.lessThan requiredKeys;
      extraKeys = builtins.filter (k: !(builtins.elem k reqKeysSorted)) allContextKeys;
      # Required keys as required (false), extra keys as optional (true)
      funcArgs = lib.genAttrs reqKeysSorted (_: false) // lib.genAttrs extraKeys (_: true);
    in
    lib.warn
      "den.lib.perCtx [${lib.concatStringsSep "," reqKeysSorted}] is deprecated — handler-based resolution makes context guards unnecessary"
      {
        __fn =
          resolvedArgs:
          let
            # If any extra key was resolved (handler exists), we're at a deeper level
            hasExtras = builtins.any (k: resolvedArgs ? ${k}) extraKeys;
          in
          if hasExtras then
            { }
          else if lib.isFunction aspect && !builtins.isAttrs aspect then
            aspect (lib.intersectAttrs (lib.genAttrs reqKeysSorted (_: null)) resolvedArgs)
          else
            aspect;
        __args = funcArgs;
      };

  perHost = perCtx [ "host" ];
  perUser = perCtx [
    "host"
    "user"
  ];
  perHome = perCtx [ "home" ];
in
{
  den.lib = { inherit perHome perUser perHost; };
}
