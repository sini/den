{
  lib,
  den,
  fx,
  ...
}:
let
  aspectPath = a: (a.meta.provider or [ ]) ++ [ (a.name or "<anon>") ];

  pathKey = path: lib.concatStringsSep "/" path;

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
      in
      {
        resume = param;
        state = state // {
          paths = (state.paths or [ ]) ++ (lib.optional (!isExcluded) (aspectPath param));
        };
      };
  };

  # Handler for get-path-set effect. Returns accumulated paths as a set.
  pathSetHandler = {
    "get-path-set" =
      { param, state }:
      let
        paths = state.paths or [ ];
        ps = toPathSet paths;
      in
      {
        resume = ps;
        inherit state;
      };
  };

in
{
  inherit
    aspectPath
    pathKey
    toPathSet
    tombstone
    collectPathsHandler
    pathSetHandler
    ;
}
