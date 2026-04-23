{ lib, ... }:
let
  # Wrap an aspect so it only resolves when __ctx keys match exactly.
  # perHost fires at host level ({ host }) but NOT user level ({ host, user }).
  #
  # Structure: { includes = [ guardedChild ] }
  # - Outer wrapper is a plain aspect — trace shows it with the aspect name
  # - Inner guardedChild is a functor with __functionArgs for the minimum
  #   required arg, so keepChild defers until some context is available
  # - guardedChild's __functor reads self.__ctx for exact-match check:
  #   returns the inner aspect on match, {} on mismatch
  # - The inner aspect appears as a traceable child (deferred or resolved)
  perCtx =
    requiredKeys: aspect:
    let
      isParametric = lib.isFunction aspect && !builtins.isAttrs aspect;
      reqKeysSorted = builtins.sort builtins.lessThan requiredKeys;
      minKey = builtins.head reqKeysSorted;
    in
    {
      includes = [
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
        }
      ];
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
