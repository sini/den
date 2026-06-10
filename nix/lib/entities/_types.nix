# nix/lib/entities/_types.nix
#
# Shared helpers for entity type definitions.
# Extracted from nix/lib/types.nix — no new functionality.
{
  lib,
  den,
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

  # Single shared production run: imports + per-scope path set from ONE fx.handle.
  # Declared as an option so the module fixpoint memoizes it — every consumer
  # (mainModule, __pathSetByScope) reads the same value, guaranteeing one resolve.
  resolveResultOption =
    den: config:
    lib.mkOption {
      internal = true;
      visible = false;
      readOnly = true;
      type = lib.types.raw;
      defaultText = "den.lib.aspects.resolveWithPaths config.class config.resolved";
      default = den.lib.aspects.resolveWithPaths config.class config.resolved;
    };

  # mainModule now derives imports from the shared result (no second run).
  mainModuleOption =
    _den: config:
    lib.mkOption {
      internal = true;
      visible = false;
      readOnly = true;
      type = lib.types.deferredModule;
      defaultText = "{ inherit (config.__resolveResult) imports; }";
      default = { inherit (config.__resolveResult) imports; };
    };

  # Per-scope path set, surfaced for the projected (in-context) hasAspect.
  pathSetByScopeOption =
    _den: config:
    lib.mkOption {
      internal = true;
      visible = false;
      readOnly = true;
      type = lib.types.raw;
      defaultText = "config.__resolveResult.pathSetByScope";
      default = config.__resolveResult.pathSetByScope;
    };

  # Entity kinds derived from the schema, excluding non-entity entries.
  schemaKinds = builtins.filter (n: n != "conf" && !(lib.hasPrefix "_" n)) (
    builtins.attrNames (den.schema or { })
  );

  # Module injected into entity submodules for resolved aspect and
  # collisionPolicy. Extracted here so host.nix, home.nix, and future entity
  # types all share it. Identity (id_hash) is owned by the schema — supplied
  # by gen-schema's mkInstanceType via mkIdentityModule — not duplicated here.
  resolvedCtxModule =
    kind:
    { config, ... }:
    {
      options.resolved = lib.mkOption {
        description = "The resolved aspect for this ${kind}.";
        readOnly = true;
        type = lib.types.raw;
        default =
          let
            isContextArg = n: builtins.elem n schemaKinds;
            ctx = lib.filterAttrs (n: v: isContextArg n && v != null) config._module.args // {
              ${kind} = config;
            };
          in
          den.lib.resolveEntity kind ctx;
      };
      options.collisionPolicy = lib.mkOption {
        description = "How to handle collisions between den context args and module-system args.";
        type = lib.types.nullOr (
          lib.types.enum [
            "error"
            "class-wins"
            "den-wins"
          ]
        );
        default = null;
      };
    };
  # System strings recognized as two-level group keys rather than host names.
  reservedSystems = lib.genAttrs lib.systems.flakeExposed (_: true);

  # Normalize mixed host declarations into canonical two-level form.
  # Two-level entries (key is a system string) pass through.
  # Flat entries (key is a host name) are grouped by their `system` attribute.
  preprocessHosts =
    raw:
    let
      systemGroups = lib.filterAttrs (k: _: reservedSystems ? ${k}) raw;
      directHosts = lib.filterAttrs (k: _: !(reservedSystems ? ${k})) raw;
      grouped = lib.foldlAttrs (
        acc: name: cfg:
        let
          system =
            cfg.system
              or (throw "den: flat host '${name}' must specify 'system' (e.g. system = \"x86_64-linux\")");
        in
        acc
        // {
          ${system} = (acc.${system} or { }) // {
            ${name} = builtins.removeAttrs cfg [ "system" ];
          };
        }
      ) { } directHosts;
    in
    lib.recursiveUpdate systemGroups grouped;
in
{
  inherit
    strOpt
    lookupAspect
    mainModuleOption
    resolveResultOption
    pathSetByScopeOption
    resolvedCtxModule
    reservedSystems
    preprocessHosts
    ;
}
