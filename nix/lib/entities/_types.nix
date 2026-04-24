# nix/lib/entities/_types.nix
#
# Shared helpers for entity type definitions.
# Extracted from nix/lib/types.nix — no new functionality.
{
  lib,
  ...
}:
let
  strOpt =
    description: default:
    lib.mkOption {
      type = lib.types.str;
      inherit description default;
    };

  # Shared aspect lookup with warning for missing aspects.
  lookupAspect =
    den: config:
    if den.aspects ? ${config.name} then
      den.aspects.${config.name}
    else
      lib.warn "den.aspects.${config.name} not defined — entity gets empty aspect" { };

  # Shared mainModule option — identical across host and home entities.
  mainModuleOption =
    den: config:
    lib.mkOption {
      internal = true;
      visible = false;
      readOnly = true;
      type = lib.types.deferredModule;
      defaultText = "den.lib.aspects.resolve config.class config.resolved";
      default = den.lib.aspects.resolve config.class config.resolved;
    };
in
{
  inherit strOpt lookupAspect mainModuleOption;
}
