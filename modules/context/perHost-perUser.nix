{ lib, ... }:
let
  # Wrap an aspect so it only resolves when __ctx keys match exactly.
  # perHost fires at host level ({ host }) but NOT user level ({ host, user }).
  #
  # Uses only the first required key in __functionArgs to defer until SOME
  # context is available. The __functor reads the full __ctx from self
  # (set by the pipeline's includeHandler) and checks exact match.
  # Returns {} on mismatch — no deferral, no drain issues.
  perCtx =
    requiredKeys: aspect:
    let
      isParametric = lib.isFunction aspect && !builtins.isAttrs aspect;
      reqKeysSorted = builtins.sort builtins.lessThan requiredKeys;
      minKey = builtins.head reqKeysSorted;
    in
    {
      __functor =
        self: _:
        let
          ctx = self.__ctx or { };
          ctxKeys = builtins.sort builtins.lessThan (builtins.attrNames ctx);
        in
        if ctxKeys == reqKeysSorted then if isParametric then aspect ctx else aspect else { };
      __functionArgs = {
        ${minKey} = false;
      };
      includes = [ ];
    };

  perHost = perCtx [ "host" ];
  perUser = perCtx [
    "host"
    "user"
  ];
  perHome = perCtx [ "home" ];
in
{
  den.lib = { inherit perHome perUser perHost; };
}
