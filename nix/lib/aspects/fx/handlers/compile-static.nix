# Effect handler: compile-static
# Gates, classifies, emits classes, resolves nested keys, resolves children.
{
  lib,
  den,
  ...
}:
let
  inherit (den.lib) fx;
  inherit (den.lib.aspects.fx) identity;
  inherit (den.lib.aspects) isMeaningfulName;
  inherit (den.lib.aspects.fx.aspect) ctxFromHandlers;
  inherit (den.lib.aspects.fx.contentUtil) unwrapContentValuesRaw;
  inherit (import ./gate-tag.nix { inherit fx; }) gateAndTag;

  inherit (import ../aspect { inherit lib den; } { inherit ctxFromHandlers; })
    registerConstraints
    ;

  parametricInternalKeys = [
    "__fn"
    "__args"
    "__parametricDepth"
    "__parametricResolvedArgs"
  ];

  # Merge multiple attrset content values per sub-key so class keys
  # collect all definitions instead of last-win overwrite.
  mergeContentValuesPerKey =
    rawValue:
    let
      cvs = rawValue.__contentValues;
      vals = map (d: d.value) cvs;
      attrVals = builtins.filter builtins.isAttrs vals;
    in
    if builtins.length attrVals <= 1 then
      unwrapContentValuesRaw rawValue
    else
      let
        allKeys = lib.unique (lib.concatMap builtins.attrNames attrVals);
        collectKey =
          key:
          let
            defsForKey = lib.concatMap (
              cv:
              if builtins.isAttrs cv.value && cv.value ? ${key} then
                [
                  {
                    inherit (cv) file;
                    value = cv.value.${key};
                  }
                ]
              else
                [ ]
            ) cvs;
            allList = builtins.all (d: builtins.isList d.value) defsForKey;
          in
          if builtins.length defsForKey == 1 then
            (builtins.head defsForKey).value
          else if allList then
            lib.concatLists (map (d: d.value) defsForKey)
          else
            {
              __contentValues = defsForKey;
              __provider = (rawValue.__provider or [ ]) ++ [ key ];
            };
      in
      lib.genAttrs allKeys collectKey;

  emitNestedAspect =
    aspect: ctx: k:
    let
      rawValue = aspect.${k};
      innerValue =
        if builtins.isAttrs rawValue && rawValue ? __contentValues then
          mergeContentValuesPerKey rawValue
        else
          rawValue;
      subAspect =
        (if builtins.isAttrs innerValue then innerValue else { })
        // {
          name = k;
          meta = (aspect.meta or { }) // {
            provider = (aspect.meta.provider or [ ]) ++ [ (aspect.name or "<anon>") ];
          };
        }
        // lib.optionalAttrs (aspect ? __scopeHandlers) { inherit (aspect) __scopeHandlers; }
        // lib.optionalAttrs (aspect ? __ctxId) { inherit (aspect) __ctxId; };
    in
    fx.send "resolve" {
      aspect = subAspect;
      identity = identity.key subAspect;
      inherit ctx;
    };
in
{
  compileStaticHandler = {
    "compile-static" =
      { param, state }:
      let
        raw = param.aspect;
        aspect = builtins.removeAttrs raw parametricInternalKeys;
        nodeIdentity = identity.key aspect;
        chainIdentity = identity.pathKey ((aspect.meta.provider or [ ]) ++ [ (aspect.name or "<anon>") ]);
        isMeaningful = isMeaningfulName (aspect.name or "<anon>");
      in
      {
        resume =
          # Step 1: gate check (dedup + constraint) — skipped on parametric re-entry
          gateAndTag { inherit param aspect; } (
            tagged:
            # Step 2: probe for class handler, classify, emit, nest, resolve-children
            fx.bind (fx.effects.hasHandler "class") (
              hasClassHandler:
              fx.bind (if hasClassHandler then fx.send "class" null else fx.pure null) (
                targetClass:
                fx.bind
                  (fx.send "classify" {
                    aspect = tagged;
                    inherit targetClass;
                  })
                  (
                    classified:
                    let
                      # Content wrappers from aspectContentType (included via
                      # den.aspects.X.Y in an includes list) carry __contentValues
                      # at the top level.  Their nested sub-keys are independent
                      # sub-aspects that should be included explicitly, not
                      # auto-walked.  Sub-aspects from emitNestedAspect and full
                      # aspects from aspectSubmodule do NOT have __contentValues
                      # at the top level, so their nested keys auto-walk normally.
                      #
                      # When the aspect's includes list references its own nested
                      # sub-keys (detected via __provider matching aspect name),
                      # the user is taking explicit control over which sub-aspects
                      # are active — suppress auto-walk, matching provides behavior.
                      includesRefsOwnNested =
                        let
                          incs = tagged.includes or [ ];
                          aspectName = tagged.name or "";
                          nestedKeySet = lib.genAttrs classified.nestedKeys (_: true);
                        in
                        builtins.any (
                          inc:
                          builtins.isAttrs inc
                          && nestedKeySet ? ${inc.name or ""}
                          && (
                            let
                              prov = inc.meta.provider or [ ];
                            in
                            prov != [ ] && lib.last prov == aspectName
                          )
                        ) incs;
                      nestedToWalk = lib.optionals (
                        !(tagged ? __contentValues) && !includesRefsOwnNested
                      ) classified.nestedKeys;
                    in
                    fx.bind
                      (fx.seq (
                        [
                          (fx.send "emit-classes" {
                            aspect = tagged;
                            classKeys = classified.classKeys;
                            pipeKeys = classified.pipeKeys or [ ];
                            identity = nodeIdentity;
                          })
                          (registerConstraints tagged)
                        ]
                        ++ map (emitNestedAspect tagged (param.ctx or { })) nestedToWalk
                      ))
                      (
                        _:
                        fx.bind (fx.send "resolve-children" {
                          aspect = tagged;
                          inherit isMeaningful chainIdentity;
                        }) (resolved: fx.pure [ resolved ])
                      )
                  )
              )
            )
          );
        inherit state;
      };
  };
}
