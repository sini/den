{ den, lib, ... }:
let
  inherit (den.lib) canTake;

  # Context guard: wraps a function so it only fires when the context
  # matches a predicate. Returns {} on mismatch. Uses self.__ctx for
  # exact-match checking (set by pipeline's includeHandler).
  guard =
    pred: fn:
    let
      args = lib.functionArgs fn;
      requiredKeys = builtins.filter (k: !args.${k}) (builtins.attrNames args);
      minKey =
        if requiredKeys != [ ] then builtins.head (builtins.sort builtins.lessThan requiredKeys) else null;
    in
    if minKey == null then
      fn
    else
      {
        __functor =
          self: _:
          let
            ctx = self.__ctx or { };
          in
          if pred ctx fn then fn ctx else { };
        __functionArgs = {
          ${minKey} = false;
        };
        includes = [ ];
      };

  take.unused = _unused: used: used;

  # exactly: fires only when ctx keys == function's required args
  take.exactly =
    fn:
    guard (
      ctx: f:
      let
        args = lib.functionArgs f;
        required = builtins.sort builtins.lessThan (
          builtins.filter (k: !args.${k}) (builtins.attrNames args)
        );
        ctxKeys = builtins.sort builtins.lessThan (builtins.attrNames ctx);
      in
      ctxKeys == required
    ) fn;

  # atLeast: fires when ALL required args are present (extras ok)
  take.atLeast = fn: guard (ctx: f: canTake.atLeast ctx f) fn;

  # upTo: fires when at least one arg matches (subset ok)
  take.upTo = fn: guard (ctx: f: canTake.upTo ctx f) fn;

  take.__functor =
    _: canTakePred: argAdapter: fn:
    guard (ctx: _: canTakePred ctx fn) fn;
in
take
