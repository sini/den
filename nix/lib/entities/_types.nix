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

  # Entity kinds derived from the schema, excluding non-entity entries.
  schemaKinds = builtins.filter (n: n != "conf" && !(lib.hasPrefix "_" n)) (
    builtins.attrNames (den.schema or { })
  );

  # Option type names whose values are safe for identity hashing.
  primitiveTypeNames = [
    "str"
    "int"
    "bool"
  ];

  # Module injected into entity submodules for resolved aspect, id_hash,
  # and collisionPolicy. Extracted here so host.nix, home.nix, and future
  # entity types all share it.
  resolvedCtxModule =
    kind:
    {
      config,
      options,
      ...
    }:
    {
      options.id_hash = lib.mkOption {
        description = ''
          Auto-computed identity hash for entity comparison.

          Derived by reflecting on all non-internal, primitive-typed
          options (str, int, bool) declared on this entity. The schema
          kind is included to prevent cross-kind collisions.

          Use `a.id_hash != b.id_hash` instead of `a != b` for entity
          comparison — Nix's `==` does deep structural comparison which
          is fragile across module system boundaries.
        '';
        readOnly = true;
        internal = true;
        type = lib.types.str;
        default =
          let
            isPrimitive =
              name: opt:
              !(lib.hasPrefix "_" name)
              && (opt ? type)
              && builtins.elem (opt.type.name or "") primitiveTypeNames
              && !(opt.internal or false);
            identityKeys = lib.sort (a: b: a < b) (builtins.attrNames (lib.filterAttrs isPrimitive options));
            encode =
              k:
              let
                v = config.${k};
              in
              "${k}=${toString v}";
            fingerprint = "${kind}|${lib.concatMapStringsSep "|" encode identityKeys}";
          in
          builtins.hashString "sha256" fingerprint;
      };
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
    resolvedCtxModule
    reservedSystems
    preprocessHosts
    ;
}
