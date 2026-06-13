# DEPRECATED context guards — kept as a thin compatibility shim.
#
# `den.lib.perHost` / `perUser` / `perHome` shipped in earlier releases. They
# are RESTORED here as aliases over the current binding rule so existing configs
# keep evaluating (and get a deprecation warning steering them to plain
# functions). Migration: use a plain function — `({ host, ... }: { ... })`.
#
# IMPORTANT — semantics changed (this is the #609 fix): the old shim returned
# `{}` whenever a deeper context key was present (a self-suppressing emulation
# of cross-scope deferral). That behavior was the bug the binding-half rewrite
# removed. The restored shim drops the self-suppression: an entity-kind arg now
# binds once at the emitting scope if in-ctx, fans out class-locally over the
# scope's descendants otherwise, and is inert if misplaced — exactly as a plain
# `{ host, ... }:` function does. So `den.lib.perHost f` is now an alias for
# `{ host, ... }: f { inherit host; }`, not the old suppress-at-deeper-scope
# guard. Configs relying on the old silent suppression were relying on #609.
{ lib, ... }:
let
  # Build a parametric wrapper requiring exactly `requiredKeys` (all required —
  # no optional "extra" keys, hence no self-suppression). The fx bind handler
  # binds these per the current rule and applies `__fn` with the resolved args.
  perCtx =
    requiredKeys: aspect:
    let
      reqSorted = builtins.sort builtins.lessThan requiredKeys;
    in
    lib.warn
      "den.lib.perCtx [${lib.concatStringsSep "," reqSorted}] is deprecated — use a plain function ({ ${lib.concatStringsSep ", " reqSorted}, ... }: ...) instead; handler-based resolution binds context args automatically"
      {
        __args = lib.genAttrs reqSorted (_: false);
        __fn =
          resolvedArgs:
          if lib.isFunction aspect && !builtins.isAttrs aspect then
            aspect (lib.intersectAttrs (lib.genAttrs reqSorted (_: null)) resolvedArgs)
          else
            aspect;
        name = aspect.name or "<perCtx>";
        meta = aspect.meta or { };
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
