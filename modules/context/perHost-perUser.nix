{ lib, ... }:
let
  perCtx =
    requiredKeys: aspect:
    let
      reqKeysSorted = builtins.sort builtins.lessThan requiredKeys;
      minKey = builtins.head reqKeysSorted;
    in
    {
      includes = [
        {
          __functionArgs = {
            ${minKey} = false;
          };
          meta.contextGuard = {
            type = "exactly";
            keys = reqKeysSorted;
            inherit aspect;
          };
          name = "<guard:${lib.concatStringsSep "," reqKeysSorted}>";
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
