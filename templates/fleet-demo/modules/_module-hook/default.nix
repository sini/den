# module-hook: Intercept and augment NixOS modules during evalModules.
#
# Wraps arbitrary NixOS module functions at evaluation time using only
# public nixpkgs APIs, injecting virtual arguments that the NixOS module
# system never sees.
#
# Technique:
#   1. Override `lib.evalModules` via `lib.extend` to pre-process the
#      modules list — wrapping function modules to intercept virtual args.
#   2. Wrap `extendModules` on the evaluation result so modules added
#      after initial evaluation (the common nixosSystem pattern) also
#      get the wrapping treatment.
#   3. For each function module, inspect `builtins.functionArgs`. If it
#      requests any virtual arg names, partially apply those values and
#      present a new function with those args stripped from the signature.
#      The module system only sees the remaining NixOS-standard args.
#   4. Recursively wrap `imports` in module return values so the hook
#      propagates through the full import tree.
#
# Public APIs used:
#   - lib.evalModules (overridden via lib.extend)
#   - lib.setFunctionArgs (preserve function arg metadata)
#   - builtins.functionArgs (introspect module function signatures)
#
# Limitations:
#   - Path modules imported by collectModules internally cannot be
#     wrapped before import. They ARE wrapped after — when the imported
#     function returns a result with `imports`, those get wrapped.
#   - The lib.extend override only affects the initial evalModules call.
#     extendModules (used by eval-config.nix) captures evalModules from
#     its closure, bypassing the override. We compensate by wrapping
#     extendModules on the result.
{ lib }:

let
  # mkHook : { virtualArgs, trace } -> { wrapModules, wrapEvalResult, mkHookedLib }
  mkHook =
    {
      virtualArgs ? { },
      trace ? false,
    }:
    let
      virtualArgNames = builtins.attrNames virtualArgs;

      traceIf = msg: val: if trace then builtins.trace msg val else val;

      # ── Module wrapping ──────────────────────────────────────────────

      wrapModules = modules: map wrapModule modules;

      wrapModule =
        m:
        if builtins.isFunction m then
          wrapFnModule m
        else if builtins.isAttrs m then
          wrapAttrModule m
        else
          m;

      wrapFnModule =
        f:
        let
          fargs = builtins.functionArgs f;
          wantedVirtual = builtins.filter (a: fargs ? ${a}) virtualArgNames;
          wantsVirtual = wantedVirtual != [ ];
        in
        if wantsVirtual then
          let
            virtualBindings = lib.genAttrs wantedVirtual (n: virtualArgs.${n});
            remainingFargs = builtins.removeAttrs fargs wantedVirtual;

            wrapped =
              args:
              let
                result = f (args // virtualBindings);
              in
              wrapResult result;
          in
          traceIf "[module-hook] injecting [${builtins.concatStringsSep ", " wantedVirtual}] | remaining: [${builtins.concatStringsSep ", " (builtins.attrNames remainingFargs)}]" (
            lib.setFunctionArgs wrapped remainingFargs
          )
        else
          let
            wrapped =
              args:
              let
                result = f args;
              in
              wrapResult result;
          in
          traceIf "[module-hook] fn passthrough | args: [${builtins.concatStringsSep ", " (builtins.attrNames fargs)}]" (
            lib.setFunctionArgs wrapped fargs
          );

      wrapAttrModule = m: if m ? imports then m // { imports = wrapModules m.imports; } else m;

      wrapResult =
        result:
        if builtins.isAttrs result && result ? imports then
          traceIf "[module-hook] wrapResult | ${toString (builtins.length result.imports)} imports" (
            result // { imports = wrapModules result.imports; }
          )
        else
          result;

      # ── evalModules result wrapping ──────────────────────────────────

      wrapEvalResult =
        result:
        if builtins.isAttrs result && result ? extendModules then
          result
          // {
            extendModules =
              args:
              let
                wrappedArgs = args // {
                  modules = wrapModules (args.modules or [ ]);
                };
                innerResult = result.extendModules wrappedArgs;
              in
              traceIf "[module-hook] extendModules | ${toString (builtins.length (args.modules or [ ]))} new modules" (
                wrapEvalResult innerResult
              );
          }
        else
          result;

      # ── lib overlay ──────────────────────────────────────────────────

      mkHookedLib =
        baseLib:
        baseLib.extend (
          final: prev: {
            evalModules =
              args:
              let
                wrappedArgs = args // {
                  modules = wrapModules (args.modules or [ ]);
                };
                result = prev.evalModules wrappedArgs;
              in
              traceIf "[module-hook] evalModules | class: ${args.class or "<none>"} | ${toString (builtins.length (args.modules or [ ]))} modules" (
                wrapEvalResult result
              );
          }
        );

    in
    {
      inherit wrapModules wrapEvalResult mkHookedLib;
    };

  # mkHookedNixosSystem : nixpkgsInput -> hookConfig -> (args -> nixosConfiguration)
  mkHookedNixosSystem =
    nixpkgs: hookConfig:
    let
      hook = mkHook hookConfig;
      hookedLib = hook.mkHookedLib nixpkgs.lib;
    in
    args:
    import (nixpkgs.outPath + "/nixos/lib/eval-config.nix") (
      { system = args.system or "x86_64-linux"; } // args // { lib = hookedLib; }
    );

in
{
  inherit mkHook mkHookedNixosSystem;
}
