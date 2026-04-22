{
  inputs,
  lib,
  config,
  ...
}:
let
  inherit (config) den;
  hostEntities = import ./../nix/lib/entities/host.nix {
    inherit
      inputs
      lib
      den
      config
      ;
  };
  homeEntities = import ./../nix/lib/entities/home.nix {
    inherit
      inputs
      lib
      den
      config
      ;
  };

  # Schema entries auto-inject config.resolved when den.stages.${kind} exists
  # or den.relationships reference the kind.
  # Context args are derived from the entity's _module.args, filtered to
  # known stage kinds so framework args don't leak through.
  knownKinds = builtins.attrNames (den.stages or { });
  schemaEntryType =
    let
      base = lib.types.deferredModule;
    in
    base
    // {
      merge =
        loc: defs:
        let
          kind = lib.last loc;
          merged = base.merge loc defs;
          resolvedCtx =
            { config, ... }:
            {
              options.resolved = lib.mkOption {
                description = "The resolved aspect for this ${kind}.";
                readOnly = true;
                type = lib.types.raw;
                default = den.lib.resolveStage kind (
                  lib.filterAttrs (n: _: builtins.elem n knownKinds) config._module.args // { ${kind} = config; }
                );
              };
            };
        in
        if den.stages ? ${kind} then
          {
            imports = [
              merged
              resolvedCtx
            ];
          }
        else
          merged;
    };

  schemaOption = lib.mkOption {
    description = "freeform deferred modules per entity kind";
    defaultText = lib.literalExpression "{ }";
    default = { };
    type = lib.types.submodule {
      freeformType = lib.types.lazyAttrsOf schemaEntryType;
    };
  };
in
{
  options.den.hosts = hostEntities.hostsOption;
  options.den.homes = homeEntities.homesOption;
  options.den.schema = schemaOption;
  config.den.schema = {
    conf = { };
    host.imports = [ den.schema.conf ];
    user.imports = [ den.schema.conf ];
    home.imports = [ den.schema.conf ];
  };
}
