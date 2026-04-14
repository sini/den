{
  lib,
  den,
  fx,
  identity,
  ...
}:
let
  inherit (identity) aspectPath pathKey;

  exclude = {
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

  substitute = {
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
  filterBy = {
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
  inherit exclude substitute filterBy;
}
