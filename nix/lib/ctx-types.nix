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
    # Declared here (not on aspectSubmodule) so ctx nodes are callable
    # via den.ctx.host { host = config; } while aspects stay plain attrsets.
    options.__functor = lib.mkOption {
      internal = true;
      visible = false;
      # Maximally lazy — takes last def without evaluating values.
      # lib.types.anything forces evaluation during recursive merge,
      # triggering config.den before it's available (circular).
      type = lib.types.mkOptionType {
        name = "lazyFunctor";
        check = _: true;
        merge = _: defs: (lib.last defs).value;
      };
    };
    # Curried lambda so lib.isFunction returns true without forcing ctxApply.
    # _: ctxApply would make isFunction evaluate the ctxApply thunk (which
    # references config.den) during module loading — circular.
    config.__functor = lib.mkForce (self: ctx: ctxApply self ctx);
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
