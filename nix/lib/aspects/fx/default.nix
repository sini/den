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

  # Pure trace handlers — no nix-effects dependency.
  pureTrace = import ./trace.nix {
    inherit lib den;
    fx = null;
    identity = pureIdentity;
  };

  # Pure constraint constructors — no nix-effects dependency.
  # Available without init for use in aspect definitions.
  pureConstraints = import ./constraints.nix {
    inherit lib den;
    fx = null;
    identity = pureIdentity;
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

  # Constraint constructors usable in aspect meta.adapter without nix-effects.
  inherit (pureConstraints)
    exclude
    substitute
    filterBy
    ;

  init =
    fx:
    let
      identity = import ./identity.nix { inherit lib den fx; };
      includes = import ./includes.nix { inherit lib den fx; };
      trace = import ./trace.nix {
        inherit
          lib
          den
          fx
          identity
          ;
      };
      constraints = import ./constraints.nix {
        inherit
          lib
          den
          fx
          identity
          ;
      };
      aspect = import ./aspect.nix { inherit lib den fx; };
      handlers = import ./handlers.nix { inherit lib den fx; };
      ctxApply = import ./ctx-apply.nix {
        inherit
          lib
          den
          fx
          identity
          ;
      };
      resolve = import ./resolve.nix {
        inherit
          lib
          den
          fx
          aspect
          handlers
          identity
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
      inherit (constraints) exclude substitute filterBy;
      inherit
        constraints
        aspect
        handlers
        identity
        includes
        resolve
        trace
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
      inherit (trace) structuredTraceHandler tracingHandler;
    };
}
