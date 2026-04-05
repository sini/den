{ lib, den, ... }:
ctxNs:
let
  inherit (den.lib) parametric;

  noop = _: { };

  flattenInto =
    attrset: prefix:
    lib.concatLists (
      lib.mapAttrsToList (
        name: v:
        let
          path = prefix ++ [ name ];
        in
        if builtins.isList v then
          [
            {
              inherit path;
              into = v;
            }
          ]
        else
          flattenInto v path
      ) attrset
    );

  resolveAspect = path: lib.attrByPath path null ctxNs;

  getCrossProvider = p: (p.prev.provides.${p.key} or (_: noop)) p.prevCtx;

  refToName = ref: if builtins.isString ref then ref else ref.name or "<anon>";

  collectExcludes =
    ctx:
    let
      fromEntity = v: if builtins.isAttrs v then map refToName (v.excludes or [ ]) else [ ];
      fromAspect =
        v:
        if builtins.isAttrs v && v ? aspect then
          map refToName ((den.aspects.${v.aspect} or { }).excludes or [ ])
        else
          [ ];
    in
    lib.genAttrs (lib.concatMap (v: fromEntity v ++ fromAspect v) (builtins.attrValues ctx)) (_: true);

  traverse =
    args@{
      prev,
      prevCtx,
      self,
      ctx,
      key,
      excluded,
    }:
    let
      selfExcludes = lib.genAttrs (map refToName (self.excludes or [ ])) (_: true);
      newExcluded = excluded // selfExcludes;

      intoList = flattenInto ((self.into or noop) ctx) [ ];
      expandOne =
        { path, into }:
        let
          aspect = resolveAspect path;
          aspectKey = lib.concatStringsSep "." path;
          pathHead = lib.head path;
          hasProvider = self.provides ? ${pathHead};
          isExcluded = newExcluded ? ${aspectKey};
        in
        if isExcluded then
          [ ]
        else if aspect != null then
          lib.concatMap (
            c:
            traverse {
              prev = self;
              prevCtx = ctx;
              self = aspect;
              ctx = c;
              key = aspectKey;
              excluded = newExcluded;
            }
          ) into
        else if builtins.length path == 1 && hasProvider then
          lib.concatMap (
            c:
            traverse {
              prev = self;
              prevCtx = ctx;
              self = {
                name = pathHead;
                into = noop;
              };
              ctx = c;
              key = pathHead;
              excluded = newExcluded;
            }
          ) into
        else
          [ ];
    in
    [ args ] ++ lib.concatMap expandOne intoList;

  buildIncludes =
    item:
    let
      isFirst = !(item.seen ? ${item.key});
      selfProvider = item.self.provides.${item.self.name} or noop;
      crossProvider = getCrossProvider item;
    in
    [
      (if isFirst then parametric.fixedTo item.ctx item.self else parametric.atLeast item.self item.ctx)
      (selfProvider item.ctx)
      (crossProvider item.ctx)
    ];

  assembleIncludes =
    items:
    let
      step = acc: item: {
        seen = acc.seen // {
          ${item.key} = true;
        };
        result = acc.result ++ (buildIncludes (item // { inherit (acc) seen; }));
      };
    in
    (lib.foldl' step {
      seen = { };
      result = [ ];
    } items).result;

  collectAspectTransforms =
    ctx:
    lib.concatMap (
      v:
      if builtins.isAttrs v && v ? aspect then (den.aspects.${v.aspect} or { }).transforms or [ ] else [ ]
    ) (builtins.attrValues ctx);

  ctxApply =
    self: ctx:
    let
      excluded = collectExcludes ctx;
      aspectTransforms = collectAspectTransforms ctx;
    in
    {
      excludes = builtins.attrNames excluded; # merged into aspectSubmodule via ctxSubmodule.__functor
      transforms = aspectTransforms;
      includes = assembleIncludes (traverse {
        prev = null;
        prevCtx = null;
        key = self.name;
        inherit self ctx;
        inherit excluded;
      });
    };

in
ctxApply
