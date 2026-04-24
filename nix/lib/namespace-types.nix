{ den, lib, ... }:
let
  inherit (den.lib.aspects) mkAspectsType;
  inherit (den.lib.stageTypes) stageTreeType;

  namespaceType = lib.types.submodule (
    nsArgs@{ name, ... }:
    {
      options.stages = lib.mkOption {
        description = "namespace stage scopes";
        defaultText = lib.literalExpression "{ }";
        default = { };
        type = lib.types.lazyAttrsOf stageTreeType;
      };
      # Compat alias: prevent ns.ctx.x from silently creating freeform aspects.
      options.ctx = lib.mkOption {
        visible = false;
        default = { };
        type = lib.types.lazyAttrsOf stageTreeType;
      };
      config.stages = lib.mkMerge (
        lib.mapAttrsToList (ctxName: value: {
          ${ctxName} = lib.warn "${name}.ctx.${ctxName} is deprecated — use ${name}.stages.${ctxName}" value;
        }) (builtins.removeAttrs nsArgs.config.ctx [ "_module" ])
      );
      options.schema = lib.mkOption {
        description = "namespace schema — freeform deferred modules per entity kind";
        defaultText = lib.literalExpression "{ }";
        default = { };
        type = lib.types.submodule {
          freeformType = lib.types.lazyAttrsOf lib.types.deferredModule;
        };
      };
      freeformType = (mkAspectsType { providerPrefix = [ name ]; }).aspectsType;
    }
  );
in
{
  inherit namespaceType;
}
