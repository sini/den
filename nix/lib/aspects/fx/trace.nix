{
  lib,
  den,
  fx,
  identity,
  ...
}:
let
  inherit (identity) aspectPath pathKey;

  # Derive parent from includesChain, filtering out self-references.
  # Mirrors legacy structuredTrace's `fp != selfFullPath` filter:
  # withIdentity wrappers from deepRecurse carry the parent's name,
  # so the chain may contain the aspect's own identity.
  chainParent =
    chain: selfPath:
    let
      filtered = builtins.filter (p: p != selfPath) chain;
    in
    if filtered == [ ] then null else lib.last filtered;

  # Trace handler that accumulates structured entries for each resolved aspect.
  # Reads __ctxStage/__ctxKind from provider-tagged aspects (set by ctxApply),
  # falls back to state.currentStage/currentKind (set by ctxTraceHandler).
  structuredTraceHandler = class: {
    "resolve-complete" =
      { param, state }:
      let
        selfPath = pathKey (aspectPath param);
        entry = {
          name = param.name or "<anon>";
          inherit class;
          parent = chainParent (state.includesChain or [ ]) selfPath;
          provider = param.meta.provider or [ ];
          excluded = param.meta.excluded or false;
          excludedFrom = param.meta.excludedFrom or null;
          replacedBy = param.meta.replacedBy or null;
          isProvider = (param.meta.provider or [ ]) != [ ];
          handlers = param.meta.handleWith or [ ];
          hasClass = param ? ${class};
          isParametric = param.meta.isParametric or false;
          fnArgNames = param.meta.fnArgNames or [ ];
          ctxStage = param.__ctxStage or (state.currentStage or null);
          ctxKind = param.__ctxKind or (state.currentKind or null);
        };
      in
      {
        resume = param;
        state = state // {
          entries = (state.entries or [ ]) ++ [ entry ];
        };
      };
  };

  # Combined resolve-complete handler for tracing: collects trace entries and paths.
  # Module collection is handled by provideClassHandler via provide-class effects.
  # Use as extraHandlers with mkPipeline.
  #
  # Disambiguates anonymous entries using context stage tags, matching the
  # legacy structuredTrace adapter's naming: stage/kind(aspect):provider.
  tracingHandler = class: {
    "resolve-complete" =
      { param, state }:
      let
        isExcluded = param.meta.excluded or false;
        rawName = param.meta.originalName or param.name or "<anon>";
        provPath = lib.concatStringsSep "/" (param.meta.provider or [ ]);
        ctxStage = param.__ctxStage or (state.currentStage or null);
        ctxKind = param.__ctxKind or (state.currentKind or null);
        ctxAspect = param.__ctxAspect or (state.currentCtxAspect or null);
        meaningful =
          n: n != "<anon>" && n != "<function body>" && !(lib.hasPrefix "[definition " n) && n != null;
        isAnon = !meaningful rawName;
        name =
          if isAnon && ctxStage != null then
            let
              stage = ctxStage;
              kind = if ctxKind != null then ctxKind else "resolve";
              aspectTag = if ctxAspect != null then "(${ctxAspect})" else "";
              provTag = lib.optionalString (provPath != "") ":${provPath}";
            in
            "${stage}/${kind}${aspectTag}${provTag}"
          else
            rawName;
        selfFullPath = if provPath != "" then "${provPath}/${name}" else name;
        parent = chainParent (state.includesChain or [ ]) selfFullPath;
        entry = {
          inherit name class parent;
          provider = param.meta.provider or [ ];
          excluded = isExcluded;
          excludedFrom = param.meta.excludedFrom or null;
          replacedBy = param.meta.replacedBy or null;
          isProvider = (param.meta.provider or [ ]) != [ ];
          handlers = param.meta.handleWith or [ ];
          hasClass = param ? ${class};
          isParametric = param.meta.isParametric or false;
          fnArgNames = param.meta.fnArgNames or [ ];
          inherit ctxStage ctxKind;
        };
      in
      {
        resume = param;
        state =
          state
          // {
            paths = (state.paths or [ ]) ++ (lib.optional (!isExcluded) (aspectPath param));
            entries = (state.entries or [ ]) ++ [ entry ];
          }
          // lib.optionalAttrs (param ? __ctxStage) {
            currentStage = param.__ctxStage;
            currentKind = param.__ctxKind or null;
            currentCtxAspect = param.__ctxAspect or null;
          };
      };
  };

in
{
  inherit structuredTraceHandler tracingHandler;
}
