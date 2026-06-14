# edge.nix — the shared delivery-edge record: constructor, the (T,P,S,M) sort
# key, and the id_hash-based scope-naming helpers. EXTRACTED from edge-trace.nix
# so that the read-only oracle (edge-trace.nix) and the production edge
# constructors (edges/default.nix) share ONE edge definition and can never
# diverge on record shape or normalization (spec §3a: extractor and constructors
# converge on one edge).
#
# Edge record:  { source; target; path; mode; annotations; }
#   S (source)  — collected(scopeName, class) | rewalk(aspect, bindings, class)
#                 | synthesize(forwardId, fromClass, intoClass)
#   T (target)  — { root = scopeName; class; }  (instantiation root)
#                 | { output = attrpath; }      (flake-output)
#   P (path)    — attrpath; [] = merge at root
#   M (mode)    — "merge" | "nest" | "nest-verbatim"
#
# Trace normalization (spec §8): sort key (T, P, S, M); entity scopes named by
# id_hash (parent-blind identity), non-entity scopes by their mkScopeId string;
# rewalk/synthesize edges record the identity triple, NOT resolved content.
{ lib, ... }:
let
  # --- scope naming -------------------------------------------------------

  # Entity kind for a scope, if any. scopeEntityKind covers scopes created by
  # `resolve.to`, but NOT the pipeline root (it is seeded from ctx, never
  # `resolve.to`-created). For the root (and any ctx-seeded entity scope), scan
  # the scope's own ctx for a kind-keyed record carrying an id_hash.
  entityKindOf =
    { scopeEntityKind, scopeContexts }:
    sid:
    let
      viaKind = scopeEntityKind.${sid} or null;
      ctx = scopeContexts.${sid} or { };
      # A ctx key whose value is an entity record (has id_hash). Sorted for
      # determinism; first wins (a scope carries one own-entity record).
      ctxKinds = lib.filter (k: builtins.isAttrs (ctx.${k} or null) && (ctx.${k} ? id_hash)) (
        lib.sort (a: b: a < b) (builtins.attrNames ctx)
      );
    in
    if viaKind != null then
      viaKind
    else if ctxKinds != [ ] then
      builtins.head ctxKinds
    else
      null;

  # id_hash of the own-entity record at a scope, if the scope is an entity scope.
  idHashOf =
    args@{ scopeEntityKind, scopeContexts }:
    sid:
    let
      kind = entityKindOf args sid;
      erec = if kind == null then null else (scopeContexts.${sid} or { }).${kind} or null;
    in
    if erec == null then null else erec.id_hash or null;

  # Stable scope NAME for S/T. Entity scopes → "<kind>:<id_hash>" (parent-blind
  # identity, stable across re-keying and same-name siblings collapse by design,
  # spec §8). Non-entity scopes (system=…, root "") → the mkScopeId string.
  scopeName =
    args@{ scopeEntityKind, scopeContexts }:
    sid:
    let
      kind = entityKindOf args sid;
      idHash = idHashOf args sid;
    in
    if kind != null && idHash != null then
      "${kind}:${idHash}"
    else
      (if sid == "" then "<root>" else sid);

  # --- edge record + sort -------------------------------------------------

  mkEdge =
    {
      source,
      target,
      path ? [ ],
      mode,
      annotations ? { },
    }:
    {
      inherit
        source
        target
        path
        mode
        annotations
        ;
    };

  # Canonical string keys for stable sort (spec §8: T, P, S, M).
  targetKey =
    t: if t ? output then "out:${lib.concatStringsSep "." t.output}" else "root:${t.root}/${t.class}";
  pathKey = p: lib.concatStringsSep "/" p;
  sourceKey =
    s:
    if s ? collected then
      "collected:${s.collected.scope}/${s.collected.class}"
    else if s ? rewalk then
      "rewalk:${s.rewalk.aspect}/${lib.concatStringsSep "+" s.rewalk.bindings}/${s.rewalk.class}"
    else if s ? synthesize then
      "synthesize:${s.synthesize.forwardId}/${s.synthesize.fromClass}>${s.synthesize.intoClass}"
    else
      "empty";
  edgeSortKey =
    e:
    lib.concatStringsSep " | " [
      (targetKey e.target)
      (pathKey e.path)
      (sourceKey e.source)
      e.mode
    ];

  sortEdges = edges: lib.sort (a: b: edgeSortKey a < edgeSortKey b) edges;

  # --- S/T constructors ---------------------------------------------------

  collected = scope: class: { collected = { inherit scope class; }; };
  rewalk = aspect: bindings: class: { rewalk = { inherit aspect bindings class; }; };
  synthesize = forwardId: fromClass: intoClass: {
    synthesize = { inherit forwardId fromClass intoClass; };
  };
  rootTarget = root: class: { inherit root class; };
  outputTarget = output: { inherit output; };
in
{
  inherit
    entityKindOf
    scopeName
    mkEdge
    sortEdges
    collected
    rewalk
    synthesize
    rootTarget
    outputTarget
    ;
}
