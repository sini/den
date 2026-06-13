# Route forward-aspect collection.
#
# The simple-route module wrapping (path nesting, guards, adaptArgs, verbatim,
# the #572 combine) moved to edges/route.nix (Task 8 — simple routes are
# delivery edges; the nest/nest-verbatim mode mechanics live in the materializer
# mode switch). Only `collectClassMods` remains here — it is consumed by the
# COMPLEX-forward path (route/apply.nix:applyComplexRoute, Task 9) to collect a
# forward aspect's class modules, NOT a route-nesting concern.
{ lib, ... }:
let
  # Collect class modules from a forward aspect (recursing into includes).
  collectClassMods =
    cls: aspect:
    let
      own = lib.optional (aspect ? ${cls}) aspect.${cls};
      nested = builtins.concatMap (collectClassMods cls) (aspect.includes or [ ]);
    in
    own ++ nested;
in
{
  inherit collectClassMods;
}
