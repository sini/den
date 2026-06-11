{
  lib,
  den,
  ...
}:
let
  aspectPath =
    a:
    (a.meta.provider or [ ]) ++ [ (a.name or "<anon>") ] ++ lib.optional (a ? __ctxId) "{${a.__ctxId}}";

  pathKey = path: lib.concatStringsSep "/" path;

  # Composed: aspectPath → pathKey in one call.
  key = a: pathKey (aspectPath a);

  # Base identity without the {ctxId} instance suffix: provider chain + name.
  # The pretty, stable fully-qualified name (e.g. "roles/workstation").
  baseKey = a: pathKey ((a.meta.provider or [ ]) ++ [ (a.name or "<anon>") ]);

  # True when an identity string refers to an anonymous/unresolved node.
  isAnonIdentity =
    id:
    !(den.lib.aspects.isMeaningfulName id) || lib.hasPrefix "<root>/" id || lib.hasInfix "/<anon>:" id;

  # Strip the {ctxId} suffix from an identity, yielding the base identity.
  stripCtxSuffix = id: lib.head (lib.splitString "/{" id);

  toPathSet =
    paths:
    builtins.listToAttrs (
      builtins.map (p: {
        name = pathKey p;
        value = true;
      }) paths
    );

  tombstone = resolved: extra: {
    name = "~${resolved.name or "<anon>"}";
    meta =
      (resolved.meta or { })
      // {
        excluded = true;
        originalName = resolved.name or "<anon>";
      }
      // extra;
    includes = [ ];
  };

  collectPathsHandler = {
    "resolve-complete" =
      { param, state }:
      let
        isExcluded = param.meta.excluded or false;
        # The entity root (host/user/home) carries __entityKind. It is indexed
        # in pathSet (unchanged) but excluded from resolvedNodes — an entity is
        # not one of its own aspects.
        isEntityRoot = param ? __entityKind;
        path = aspectPath param;
        nodeKey = pathKey path;
        # Also store base path (without ctxId) so hasAspect can match
        # without needing to know the specific context instance.
        nodeBaseKey = baseKey param;
      in
      {
        resume = param;
        state =
          state
          // lib.optionalAttrs (!isExcluded) {
            pathSet =
              _:
              (state.pathSet or (_: { })) null
              // {
                ${nodeKey} = true;
              }
              // lib.optionalAttrs (nodeBaseKey != nodeKey) {
                ${nodeBaseKey} = true;
              };
            pathSetByScope =
              _:
              let
                prev = (state.pathSetByScope or (_: { })) null;
                scope = state.currentScope;
                scopeSet = prev.${scope} or { };
              in
              prev
              // {
                ${scope} = scopeSet // {
                  ${nodeBaseKey} = true;
                };
              };
          }
          // lib.optionalAttrs (!isExcluded && !isEntityRoot) {
            # Full resolved nodes keyed by unique (ctx-qualified) identity, for
            # host.aspects. Stored behind the state thunk so a deepSeq of state
            # never forces the node's class-content bodies (the lambda is WHNF);
            # only reading host.aspects materializes name/meta/identity.
            resolvedNodes =
              _:
              (state.resolvedNodes or (_: { })) null
              // {
                ${nodeKey} = param;
              };
          };
      };
  };

  pathSetHandler = {
    "get-path-set" =
      { param, state }:
      {
        resume = (state.pathSet or (_: { })) null;
        inherit state;
      };
  };

in
{
  inherit
    aspectPath
    pathKey
    key
    baseKey
    isAnonIdentity
    stripCtxSuffix
    toPathSet
    tombstone
    collectPathsHandler
    pathSetHandler
    ;
}
