{ den, lib, ... }:
let
  carryAttrs =
    fn: result:
    if builtins.isAttrs result then
      result
      // lib.optionalAttrs ((fn.name or null) != null && !(result ? name)) { inherit (fn) name; }
      // lib.optionalAttrs ((fn.excludes or [ ]) != [ ] && !(result ? excludes)) {
        inherit (fn) excludes;
      }
    else
      result;

  take.unused = _unused: used: used;
  take.exactly = take den.lib.canTake.exactly;
  take.atLeast = take den.lib.canTake.atLeast;
  take.__functor =
    _: takes: fn: ctx:
    if takes ctx fn then carryAttrs fn (fn ctx) else { };
in
take
