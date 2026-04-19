{ lib, den, ... }:
ctxApply:
let

  # Deep merge for into results: recurse into nested attrsets,
  # concatenate lists at leaves (multiple into defs contribute
  # context values to the same target).
  mergeInto =
    a: b:
    a
    // builtins.mapAttrs (
      k: vb:
      if a ? ${k} then
        let
          va = a.${k};
        in
        if builtins.isList va && builtins.isList vb then
          va ++ vb
        else if builtins.isAttrs va && builtins.isAttrs vb then
          mergeInto va vb
        else
          vb
      else
        vb
    ) b;

  # into values are functions: ctx → { targetName = [ctxValues]; ... }
  # Non-function defs are normalized to functions during merge.
  intoCtxType = lib.types.mkOptionType {
    name = "into";
    description = "context transition function (ctx → targets attrset)";
    check = v: lib.isFunction v || builtins.isAttrs v;
    merge =
      _loc: defs:
      let
        normalized = map (d: d // { value = normalize d.value; }) defs;
      in
      ctx: lib.foldl' (acc: d: mergeInto acc (d.value ctx)) { } normalized;
  };

  # Normalize into defs: function defs pass through. Attrset defs become
  # functions that call each value with ctx. Recurses into nested attrsets
  # so into.ns.inner = lib.singleton works (calls inner fn with ctx).
  normalize =
    def:
    if lib.isFunction def then
      def
    else
      ctx:
      builtins.mapAttrs (
        _: v:
        if lib.isFunction v then
          v ctx
        else if builtins.isAttrs v then
          (normalize v) ctx
        else
          v
      ) def;

  ctxSubmodule = lib.types.submodule {
    imports = den.lib.aspects.types.aspectType.getSubModules;
    options.into = lib.mkOption {
      description = "Context transformations to other context types";
      type = intoCtxType;
      defaultText = lib.literalExpression "_: { }";
      default = _: { };
    };
    config.__functor = lib.mkForce ctxApply;
  };

  ctxTreeType = lib.types.mkOptionType {
    name = "ctxTree";
    description = "ctx definition or namespace";
    check = lib.isAttrs;
    merge =
      loc: defs:
      let
        ctxNodeKeys = [
          "into"
          "provides"
          "_"
          "includes"
          "__functor"
          "_module"
        ];
        hasKey = x: builtins.any (k: x ? ${k}) ctxNodeKeys;
        isLeaf = lib.any (d: hasKey d.value) defs;
      in
      if isLeaf then ctxSubmodule.merge loc defs else (lib.types.lazyAttrsOf ctxTreeType).merge loc defs;
    emptyValue = {
      value = { };
    };
  };

in
{
  inherit ctxTreeType;
}
