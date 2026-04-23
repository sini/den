# Compatibility shim: forwards den.ctx.* to den.stages.* with deprecation warnings.
# den.ctx was always flat (host, user, hm-host — never nested namespaces),
# so we use stageSubmodule directly instead of stageTreeType.
# Remove after downstream users have migrated.
{
  den,
  lib,
  config,
  ...
}:
let
  inherit (den.lib.stageTypes) stageSubmodule;
in
{
  options.den.ctx = lib.mkOption {
    description = "DEPRECATED: use den.stages instead.";
    default = { };
    type = lib.types.lazyAttrsOf stageSubmodule;
  };

  config.den.stages = lib.mkMerge (
    lib.mapAttrsToList (name: value: {
      ${name} = lib.warn "den.ctx.${name} is deprecated — use den.stages.${name}" value;
    }) (builtins.removeAttrs config.den.ctx [ "_module" ])
  );
}
