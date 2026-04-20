{ den, lib, ... }:
let
  inherit (den.lib) canTake;

  mkGuard =
    type: fn:
    let
      args = lib.functionArgs fn;
      requiredKeys = builtins.filter (k: !args.${k}) (builtins.attrNames args);
      sortedKeys = builtins.sort builtins.lessThan requiredKeys;
      minKey = if sortedKeys != [ ] then builtins.head sortedKeys else null;
    in
    if minKey == null then
      fn
    else
      {
        __functionArgs = {
          ${minKey} = false;
        };
        meta.contextGuard = {
          inherit type;
          keys = sortedKeys;
          aspect = fn;
        };
        includes = [ ];
      };

  take.unused = _unused: used: used;
  take.exactly = mkGuard "exactly";
  take.atLeast = mkGuard "atLeast";
  take.upTo = mkGuard "upTo";

  # Deprecated: custom predicate form. Best-effort shim using atLeast.
  take.__functor =
    _: _canTakePred: _argAdapter: fn:
    lib.warn "den.lib.take custom predicate is deprecated — use take.exactly/atLeast/upTo" (
      mkGuard "atLeast" fn
    );
in
take
