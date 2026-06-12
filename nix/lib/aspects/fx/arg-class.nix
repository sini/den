# Pure classification of parametric-aspect args against the schema entity DAG.
# An entity-kind arg at scope-kind `scopeKind` is either bindable from ctx
# (handled upstream in bind), a DESCENDANT (relationship fan-out at the
# emitting scope), or misplaced (inert). Non-entity args never reach this.
#
# Child enumeration is convention-based: a parent record holds its `kind`
# children in attr "${kind}s" (host.users; nix-config's guest kind follows
# the same convention with host.guests — note `guest` is NOT in den's
# default schema). A schema-declared override is deliberately deferred
# until a consumer needs one (YAGNI; both known collections follow the
# convention).
#
# Related: resolve.nix's isAncestorOf walks scope-parent chains (different
# map shape, self-loop guard only) — keep the two in mind if either changes.
{ ... }:
rec {
  # True when argKind's parent chain reaches scopeKind (strict descendant).
  isDescendantOf =
    schema: scopeKind: argKind:
    let
      walk =
        k: seen:
        let
          p = schema.${k}.parent or null;
        in
        if p == null || builtins.elem p seen then
          false
        else if p == scopeKind then
          true
        else
          walk p (seen ++ [ k ]);
    in
    scopeKind != null && argKind != scopeKind && walk argKind [ argKind ];

  childrenAttrFor = argKind: "${argKind}s";

  # Child records of `parentRecord` for `argKind`; [ ] when absent.
  childrenOf =
    parentRecord: argKind: builtins.attrValues (parentRecord.${childrenAttrFor argKind} or { });
}
