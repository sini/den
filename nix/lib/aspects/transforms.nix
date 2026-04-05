{ lib, ... }:
let
  normalizeResult =
    raw:
    if raw == null then
      { result = null; }
    else if raw ? result then
      { inherit (raw) result; }
    else if builtins.isAttrs raw then
      { result = raw; }
    else
      throw "transform must return an aspect attrset, null, or { result; }";

  id = { provided, ... }: provided;

  toAspectPath =
    ref:
    if builtins.isList ref then
      ref
    else if builtins.isString ref then
      [ ref ]
    else
      (ref.__provider or [ ]) ++ [ (ref.name or (throw "excludes: expected a named aspect")) ];

  isPrefix = prefix: path: prefix != [ ] && lib.take (builtins.length prefix) path == prefix;

  aspectPath = provided: (provided.__provider or [ ]) ++ [ (provided.name or "<anon>") ];

  exclude =
    refs:
    let
      paths = map toAspectPath refs;
      isExcluded = ap: builtins.any (p: p == ap || isPrefix p ap) paths;
    in
    { provided, ... }:
    if isExcluded (aspectPath provided) then null else provided;

  substitute =
    ref: replacement:
    let
      refPath = toAspectPath ref;
    in
    { provided, ... }:
    let
      ap = aspectPath provided;
    in
    if ap == refPath then
      replacement
    else if isPrefix refPath ap then
      (replacement.provides or { }).${provided.name} or null
    else
      provided;

  compose =
    transforms: ctx:
    builtins.foldl' (
      acc: f: if acc == null then null else (normalizeResult (f (ctx // { provided = acc; }))).result
    ) ctx.provided transforms;

in
{
  inherit
    normalizeResult
    id
    exclude
    substitute
    compose
    isPrefix
    toAspectPath
    aspectPath
    ;
}
