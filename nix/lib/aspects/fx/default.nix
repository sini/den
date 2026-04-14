{ lib, den, ... }:
let
  # Pure identity utilities — no nix-effects dependency.
  pureIdentity = import ./identity.nix {
    inherit lib den;
    fx = null;
  };

  # Pure includes constructors — no nix-effects dependency.
  pureIncludes = import ./includes.nix {
    inherit lib den;
    fx = null;
  };

  # Pure adapter constructors — no nix-effects dependency.
  # Available without init for use in aspect definitions.
  pureAdapters = import ./adapters.nix {
    inherit lib den;
    fx = null;
    identity = pureIdentity;
    includes = pureIncludes;
  };
in
{
  # Identity utilities usable without nix-effects.
  inherit (pureIdentity)
    aspectPath
    pathKey
    toPathSet
    tombstone
    ;

  # Includes constructors usable in aspect definitions without nix-effects.
  inherit (pureIncludes) includeIf;

  # Adapter constructors usable in aspect meta.adapter without nix-effects.
  inherit (pureAdapters)
    excludeAspect
    substituteAspect
    filterAspect
    ;

  init =
    fx:
    let
      identity = import ./identity.nix { inherit lib den fx; };
      includes = import ./includes.nix { inherit lib den fx; };
      adapters = import ./adapters.nix {
        inherit
          lib
          den
          fx
          identity
          includes
          ;
      };
      aspect = import ./aspect.nix { inherit lib den fx; };
      handlers = import ./handlers.nix { inherit lib den fx; };
      ctxApply = import ./ctx-apply.nix {
        inherit
          lib
          den
          fx
          adapters
          ;
      };
      resolve = import ./resolve.nix {
        inherit
          lib
          den
          fx
          aspect
          handlers
          adapters
          ctxApply
          ;
      };
    in
    {
      inherit (aspect) wrapAspect;
      inherit (handlers)
        parametricHandler
        staticHandler
        contextHandlers
        missingArgError
        ctxSeenHandler
        ctxProviderHandler
        ctxTraverseHandler
        ctxTraceHandler
        ctxEmitHandler
        adapterRegistryHandler
        provideClassHandler
        chainHandler
        ;
      inherit (resolve)
        resolveOne
        resolveOneStrict
        resolveDeep
        resolveDeepEffectful
        fxFullResolve
        fxResolve
        mkPipeline
        defaultHandlers
        defaultState
        composeHandlers
        wrapIdentity
        ;
      inherit ctxApply;
      inherit
        adapters
        aspect
        handlers
        identity
        includes
        resolve
        ;
      inherit (identity)
        aspectPath
        pathKey
        toPathSet
        tombstone
        collectPathsHandler
        pathSetHandler
        ;
      inherit (includes) includeIf;
    };
}
