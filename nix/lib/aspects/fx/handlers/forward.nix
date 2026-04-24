# Handles: emit-forward
# Resolves forwarded source within the current pipeline's context,
# then delegates to aspectToEffect for class key emission and filtering.
{
  lib,
  den,
  ...
}:
let
  fx = den.lib.fx;
  inherit (den.lib.aspects.fx.aspect) aspectToEffect;
  inherit (den.lib.aspects) normalizeRoot;

  mkDirectAspect =
    {
      intoClass,
      staticIntoPath,
      evalConfig,
      freeformMod,
    }:
    sourceModule:
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
        ${intoClass} = lib.setAttrByPath staticIntoPath (
          builtins.removeAttrs evaluated.config [ "_module" ]
        );
      }
    else
      {
        ${intoClass} = lib.setAttrByPath staticIntoPath (_: {
          imports = [ sourceModule ];
        });
        meta.contextDependent = true;
      };

  mkAdapterAspect =
    {
      intoClass,
      adapterKey,
      guardFn,
      guardArgs,
      intoPathArgs,
      intoPathFn,
      adaptArgsFn,
      adaptArgv,
      adapterMods,
      freeformMod,
    }:
    sourceModule: {
      meta.contextDependent = true;
      includes = [
        (mkDirectAspect {
          inherit intoClass freeformMod;
          staticIntoPath = [
            "den"
            "fwd"
            adapterKey
          ];
          evalConfig = false;
        } sourceModule)
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

  mkTopLevelAdapterAspect =
    {
      intoClass,
      guardFn,
      guardArgs,
      extraArgsFor,
      canDirectImport,
      adapterMods,
    }:
    sourceModule: {
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

  # Build the same aspect shape the old forwardItem produced,
  # but with sourceModule resolved using the parent pipeline's context.
  buildForwardAspect =
    spec: sourceModule:
    let
      base = {
        includes = [ ];
        meta = { };
      };
      body =
        if spec.needsTopLevelAdapter then
          mkTopLevelAdapterAspect {
            inherit (spec)
              intoClass
              guardFn
              guardArgs
              extraArgsFor
              canDirectImport
              adapterMods
              ;
          } sourceModule
        else if spec.needsAdapter then
          mkAdapterAspect {
            inherit (spec)
              intoClass
              adapterKey
              guardFn
              guardArgs
              intoPathArgs
              intoPathFn
              adaptArgsFn
              adaptArgv
              adapterMods
              freeformMod
              ;
          } sourceModule
        else
          mkDirectAspect {
            inherit (spec)
              intoClass
              staticIntoPath
              evalConfig
              freeformMod
              ;
          } sourceModule;
    in
    base // body;

  forwardHandler = {
    "emit-forward" =
      { param, state }:
      let
        spec = param;
        normalizedSource = normalizeRoot spec.sourceAspect;

        # Resolve source in sub-pipeline. Merge parent context (host,
        # user, system, etc.) so parametric includes can resolve, but
        # filter pipeline-internal keys that would conflict with the
        # sub-pipeline's own class/aspect-chain.
        # Propagate parent context to sub-pipeline so parametric
        # includes can resolve (e.g., { host, ... }: needs host).
        # Filter: keep only attrset values (entities like host, user)
        # and drop scalars/functions (system, output, class,
        # aspect-chain) that are pipeline-internal or could cause
        # unexpected handler matching in the sub-pipeline.
        # Source context takes priority (explicitly set by fromCtx).
        # Propagate parent entity context to sub-pipeline when the
        # source has no context of its own. Sources with explicit
        # context (fromCtx, fixedTo with __scopeHandlers) use theirs;
        # sources without any context (e.g., lib.head aspect-chain)
        # get parent entities so parametric includes can resolve.
        parentCtx = (state.currentCtx or (_: { })) null;
        entityCtx = lib.filterAttrs (_: builtins.isAttrs) parentCtx;
        sourceCtx = spec.sourceAspect.__ctx or { };
        hasOwnContext = sourceCtx != { } || (spec.sourceAspect.__scopeHandlers or { }) != { };
        resolveCtx = if hasOwnContext then sourceCtx else entityCtx;

        sourceResult = den.lib.aspects.fx.pipeline.fxFullResolve {
          class = spec.fromClass;
          self = normalizedSource;
          ctx = resolveCtx;
        };

        rawSourceModule = {
          imports = sourceResult.state.imports null;
        };
        sourceModule = spec.mapModule rawSourceModule;

        forwardAspect = buildForwardAspect spec sourceModule;
      in
      {
        # Re-emit as a regular include so the pipeline's normal mechanisms
        # (class key filtering, chain tracking, etc.) handle it exactly
        # like the old inline forward result.
        resume = fx.send "emit-include" {
          child = forwardAspect;
          idx = null;
        };
        inherit state;
      };
  };

in
{
  inherit forwardHandler;
}
