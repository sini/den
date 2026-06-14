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

  # True when `k` names a registered entity kind in `schema`.
  isEntityKind = schema: k: builtins.isAttrs (schema.${k} or null) && (schema.${k}.isEntity or false);

  childrenAttrFor = argKind: "${argKind}s";

  # Child records of `parentRecord` for `argKind`; [ ] when absent.
  childrenOf =
    parentRecord: argKind: builtins.attrValues (parentRecord.${childrenAttrFor argKind} or { });

  # Immediate parent KIND of `argKind` for a fan at scope kind `scopeKind`: the
  # schema-declared parent, falling back to the scope itself (a direct child).
  # Pure schema-DAG knowledge — kept here, not inlined in the bind handler.
  parentKindOf =
    schema: scopeKind: argKind:
    schema.${argKind}.parent or scopeKind;

  # Descendants whose immediate parent kind has a record available NOW
  # (`availRecords` keyed by kind: the scope ctx + intermediates already fanned).
  # Fanning one of these first lets the recursion reach deeper descendants once
  # their parent is bound — the shallowest-reachable order a transitive DAG fan
  # needs (a chain must bind the intermediate before its child).
  fanableDescendants =
    schema: scopeKind: availRecords: descendants:
    builtins.filter (
      k:
      let
        p = parentKindOf schema scopeKind k;
      in
      p != null && availRecords ? ${p}
    ) descendants;
}
