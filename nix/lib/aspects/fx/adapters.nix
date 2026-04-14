{
  lib,
  den,
  fx,
  identity,
  includes,
  trace,
  ...
}:
let
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

  excludeAspect = {
    __functor = _: ref: {
      type = "exclude";
      scope = "subtree";
      identity = pathKey (aspectPath ref);
    };
    global = ref: {
      type = "exclude";
      scope = "global";
      identity = pathKey (aspectPath ref);
    };
  };

  substituteAspect = {
    __functor = _: ref: replacement: {
      type = "substitute";
      scope = "subtree";
      identity = pathKey (aspectPath ref);
      replacementName = replacement.name or "<anon>";
      getReplacement = _: replacement;
    };
    global = ref: replacement: {
      type = "substitute";
      scope = "global";
      identity = pathKey (aspectPath ref);
      replacementName = replacement.name or "<anon>";
      getReplacement = _: replacement;
    };
  };

  # Predicate-based filter. Excludes aspects where pred returns false.
  # pred receives the aspect attrset (with name, meta, includes, etc).
  filterAspect = {
    __functor = _: pred: {
      type = "filter";
      scope = "subtree";
      predicate = pred;
    };
    global = pred: {
      type = "filter";
      scope = "global";
      predicate = pred;
    };
  };

in
{
  inherit
    aspectPath
    pathKey
    toPathSet
    tombstone
    excludeAspect
    substituteAspect
    filterAspect
    collectPathsHandler
    includeIf
    pathSetHandler
    structuredTraceHandler
    tracingHandler
    ;
}
