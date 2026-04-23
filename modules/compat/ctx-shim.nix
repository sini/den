# Compatibility shim: forwards den.ctx.* to den.stages.* with deprecation warnings.
# den.ctx was always flat (host, user, hm-host — never nested namespaces).
# Also handles den.ctx.*.into by forwarding to den.stages.*.meta.into.
# Remove after downstream users have migrated.
{
  den,
  lib,
  config,
  ...
}:
let
  # Extends stageSubmodule with an into option (stages don't have into,
  # but the old den.ctx did). The into value is forwarded to meta.into
  # where the pipeline already reads it.
  ctxSubmodule = lib.types.submodule {
    imports = den.lib.aspects.types.aspectType.getSubModules;
    options.into = lib.mkOption {
      description = "DEPRECATED: use den.policies instead.";
      type = lib.types.nullOr lib.types.raw;
      default = null;
    };
  };
in
{
  options.den.ctx = lib.mkOption {
    description = "DEPRECATED: use den.stages instead.";
    default = { };
    type = lib.types.lazyAttrsOf ctxSubmodule;
  };

  config.den.stages = lib.mkMerge (
    lib.mapAttrsToList (
      name: value:
      let
        intoFn = value.into or null;
        stageValue = builtins.removeAttrs value [ "into" ];
      in
      {
        ${name} =
          lib.warn "den.ctx.${name} is deprecated — use den.stages.${name}" stageValue
          // lib.optionalAttrs (intoFn != null) {
            meta.into = lib.warn "den.ctx.${name}.into is deprecated — use den.policies" intoFn;
          };
      }
    ) (builtins.removeAttrs config.den.ctx [ "_module" ])
  );
}
