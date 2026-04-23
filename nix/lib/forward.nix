{ den, lib, ... }:
let
  # Build a direct forward: resolve source and set at target path.
  mkDirectForward =
    {
      intoClass,
      evalConfig,
      sourceModule,
      freeformMod,
    }:
    path:
    if evalConfig then
      let
        evaluated = lib.evalModules {
          modules = [
            freeformMod
            sourceModule
          ];
        };
      in
      {
        ${intoClass} = lib.setAttrByPath path (builtins.removeAttrs evaluated.config [ "_module" ]);
      }
    else
      let
        value = lib.setAttrByPath path (_: {
          imports = [ sourceModule ];
        });
      in
      {
        ${intoClass} = value;
        meta.contextDependent = true;
      };

  # Build an adapter forward: wraps source in a submodule with specialArgs.
  mkAdapter =
    {
      fromClass,
      intoClass,
      sourceModule,
      freeformMod,
      adapterMods,
      adapterKey,
      guardFn,
      guardArgs,
      intoPathArgs,
      intoPathFn,
      adaptArgsFn,
      adaptArgv,
    }:
    {
      meta.contextDependent = true;
      includes = [
        (mkDirectForward
          {
            inherit intoClass freeformMod sourceModule;
            evalConfig = false;
          }
          [
            "den"
            "fwd"
            adapterKey
          ]
        )
      ];
      ${intoClass} = {
        __functionArgs = guardArgs // intoPathArgs // adaptArgv;
        __functor = _: args: {
          options.den.fwd.${adapterKey} = lib.mkOption {
            defaultText = lib.literalExpression "{ }";
            default = { };
            type = lib.types.submoduleWith {
              specialArgs = adaptArgsFn args;
              modules = adapterMods;
            };
          };
          config = guardFn args (lib.setAttrByPath (intoPathFn args) args.config.den.fwd.${adapterKey});
        };
      };
    };

  # Build a top-level adapter: like adapter but for intoPath == [].
  mkTopLevelAdapter =
    {
      intoClass,
      sourceModule,
      freeformMod,
      adapterMods,
      adapterModule,
      guardFn,
      guardArgs,
      extraArgsFor,
      canDirectImport,
    }:
    {
      meta.contextDependent = true;
      ${intoClass} = {
        __functionArgs = guardArgs;
        __functor =
          _: args:
          let
            fullArgs = args // extraArgsFor args;
          in
          if canDirectImport then
            {
              imports = [ (guardTree (guardFn args) fullArgs sourceModule) ];
            }
          else
            evalImport {
              inherit
                adapterMods
                sourceModule
                extraArgsFor
                guardFn
                ;
            } args;
      };
    };

  guardTree =
    guard: outerArgs: node:
    if builtins.isAttrs node && node ? imports then
      { imports = map (guardTree guard outerArgs) node.imports; }
    else
      _modArgs: {
        config = guard (if lib.isFunction node then node outerArgs else node);
      };

  evalImport =
    {
      adapterMods,
      sourceModule,
      extraArgsFor,
      guardFn,
    }:
    args:
    let
      extraArgs = extraArgsFor args;
      specialArgs =
        builtins.removeAttrs args [
          "config"
          "options"
          "lib"
        ]
        // extraArgs;
      evaluated = lib.evalModules {
        inherit specialArgs;
        modules = adapterMods ++ [
          sourceModule
        ];
      };
    in
    guardFn args evaluated.config;

  forwardItem =
    {
      item,
      guard ? null,
      adaptArgs ? null,
      adapterModule ? null,
      evalConfig ? false,
      ...
    }@fwd:
    let
      fromClass = fwd.fromClass item;
      intoClass = fwd.intoClass item;
      intoPath = fwd.intoPath item;
      mapModule = (fwd.mapModule or (_: lib.id)) item;

      intoPathArgs = if lib.isFunction intoPath then lib.functionArgs intoPath else { };
      intoPathFn = if lib.isFunction intoPath then intoPath else _: intoPath;
      staticIntoPath = if lib.isFunction intoPath then [ ] else intoPath;

      rawAsp = if fwd ? fromAspect then fwd.fromAspect item else item.resolved or item;
      asp =
        if fwd ? fromCtx && builtins.isAttrs rawAsp && !(builtins.isFunction rawAsp) then
          let
            ctx = fwd.fromCtx item;
            inherit (den.lib.aspects.fx.handlers) constantHandler;
          in
          rawAsp
          // {
            __ctx = ctx;
            __scopeHandlers = (rawAsp.__scopeHandlers or { }) // constantHandler ctx;
          }
        else
          rawAsp;
      sourceModule = mapModule (den.lib.aspects.resolve fromClass asp);

      freeformMod = {
        config._module.freeformType = lib.types.lazyAttrsOf lib.types.unspecified;
      };

      adapterMods = [
        freeformMod
        (
          if lib.isFunction adapterModule then
            adapterModule item
          else if builtins.isAttrs adapterModule then
            adapterModule
          else
            { }
        )
      ];

      adapterKey = lib.concatStringsSep "/" (
        [
          fromClass
          intoClass
        ]
        ++ staticIntoPath
      );

      guardArgs = if guard == null then { } else lib.functionArgs guard;
      guardFn =
        if guard == null then
          _: lib.id
        else
          args:
          let
            res = guard args;
          in
          if lib.isFunction res then res item else lib.optionalAttrs res;

      adaptArgsFn =
        args:
        if adaptArgs == null then
          args
        else
          let
            res = adaptArgs args;
          in
          if lib.isFunction res then res item else res;
      adaptArgv = if adaptArgs == null then { } else lib.functionArgs adaptArgs;

      extraArgsFor = args: builtins.removeAttrs (adaptArgsFn args) (builtins.attrNames args);
      canDirectImport = adapterModule == null;

      needsAdapter =
        guard != null || adaptArgs != null || adapterModule != null || builtins.isFunction intoPath;
      needsTopLevelAdapter = needsAdapter && intoPath == [ ];
    in
    if needsTopLevelAdapter then
      mkTopLevelAdapter {
        inherit
          intoClass
          sourceModule
          freeformMod
          adapterMods
          adapterModule
          guardFn
          guardArgs
          extraArgsFor
          canDirectImport
          ;
      }
    else if needsAdapter then
      mkAdapter {
        inherit
          fromClass
          intoClass
          sourceModule
          freeformMod
          adapterMods
          adapterKey
          guardFn
          guardArgs
          intoPathArgs
          intoPathFn
          adaptArgsFn
          adaptArgv
          ;
      }
    else
      mkDirectForward {
        inherit
          intoClass
          evalConfig
          sourceModule
          freeformMod
          ;
      } intoPath;

  forwardEach = fwd: {
    includes = map (item: forwardItem (fwd // { inherit item; })) fwd.each;
  };

in
{
  inherit forwardEach;
}
