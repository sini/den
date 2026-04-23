{ lib, den, ... }:
let
  inherit (den.lib) canTake;

  isSubmoduleFn = canTake.upTo {
    lib = true;
    config = true;
    options = true;
  };

  # Aspects are submodules with freeform class keys (nixos, homeManager, etc.)
  # plus structural options (name, meta, includes, provides).
  #
  # Functions with named args (like { host, ... }: { nixos = ...; }) are
  # coerced to { includes = [fn]; } so the fx pipeline resolves them via
  # bind.fn effects. NixOS module functions (taking lib/config/options) are
  # NOT coerced — they're handled by wrapChild's normalizeModuleFn.

  parametricType = lib.types.mkOptionType {
    name = "parametric";
    description = "parametric aspect wrapper awaiting bind.fn resolution";
    check = v: builtins.isAttrs v && v ? __fn && v ? __args;
    merge = _: defs: (lib.last defs).value;
  };

  isParametricWrapper = v: builtins.isAttrs v && v ? __fn && v ? __args;

  aspectType =
    cnf:
    let
      sub = aspectSubmodule cnf;
    in
    sub // { merge = mergeWithAspectMeta sub; };

  # Resolve parametric includes in an aspect with the given args.
  # Used by __functor so aspects are callable: (aspect { host = ...; }).
  # Directly resolvable includes (__fn/__args wrappers) are called;
  # the result is tagged with __ctx and __scopeHandlers so the pipeline
  # can resolve remaining parametric children.
  resolveAspectWith =
    self: args:
    let
      inherit (den.lib.aspects.fx.handlers) constantHandler;
      resolveInc =
        inc:
        if builtins.isAttrs inc && inc ? __fn && inc ? __args then
          let
            fn = inc.__fn;
            fnArgs = inc.__args;
            required = builtins.attrNames (lib.filterAttrs (_: v: !v) fnArgs);
            canResolve = builtins.all (k: args ? ${k}) required;
          in
          if canResolve then fn args else inc
        else
          inc;
      resolvedIncludes = map resolveInc (self.includes or [ ]);
    in
    builtins.removeAttrs self [ "_module" ]
    // {
      includes = resolvedIncludes;
      __ctx = args;
      __scopeHandlers = constantHandler args;
    };

  mergeWithAspectMeta =
    sub: loc: defs:
    let
      # Rescue explicit __functor from defs before the submodule merge
      # destroys it (freeform keys become deferred modules).
      # Providers like den.provides.forward define their own __functor.
      explicitFunctors = builtins.filter (
        d: builtins.isAttrs (d.value or null) && (d.value or { }) ? __functor
      ) defs;
      originalFunctor =
        if explicitFunctors != [ ] then (lib.last explicitFunctors).value.__functor else null;
      merged = sub.merge loc (
        defs
        ++ [
          {
            file = (lib.last defs).file;
            value = aspectMeta loc defs;
          }
        ]
      );
    in
    # Add __functor so merged aspects are callable — replaces the old
    # ctx __functor that was removed with den.ctx. Preserve explicit
    # functors (e.g. den.provides.forward).
    merged
    // {
      __functor = if originalFunctor != null then originalFunctor else resolveAspectWith;
    };

  aspectMeta =
    loc: defs:
    { config, ... }:
    let
      names = map (x: if builtins.isString x then x else "<anon>") config.meta.loc;
      nameFromLoc = lib.concatStringsSep "." names;
    in
    {
      meta.name = lib.mkForce nameFromLoc;
      meta.file = lib.mkForce (lib.last defs).file;
      meta.loc = lib.mkForce loc;
    };

  providerType =
    cnf:
    let
      at = aspectType cnf;
    in
    lib.types.mkOptionType {
      name = "provider";
      description = "aspect or function returning aspect";
      check = v: builtins.isAttrs v || lib.isFunction v;
      merge =
        loc: defs:
        let
          parametrics = builtins.filter (d: isParametricWrapper d.value) defs;
        in
        if parametrics != [ ] then
          let
            wrapper = (lib.last parametrics).value;
            nameFromLoc = lib.last loc;
          in
          wrapper // lib.optionalAttrs (!(wrapper ? name) || wrapper.name == "<anon>") { name = nameFromLoc; }
        else
          let
            nonParametrics = builtins.filter (d: !isParametricWrapper d.value) defs;
            hasFns = builtins.any (d: lib.isFunction d.value) nonParametrics;
            hasNonFns = builtins.any (d: !lib.isFunction d.value) nonParametrics;
            isMixed = hasFns && hasNonFns;
          in
          if isMixed then
            # Mixed function + attrset defs: coerce parametric functions to
            # { includes = [fn]; } so they merge as aspects.
            at.merge loc (
              map (
                d:
                if lib.isFunction d.value && !isSubmoduleFn d.value then
                  d
                  // {
                    value = {
                      includes = [ d.value ];
                    };
                  }
                else
                  d
              ) nonParametrics
            )
          else if hasFns then
            # All functions: submodule fns merge through aspectType
            # (preserving loc/name/identity). Bare parametric fns use lastFunctionTo.
            let
              subFns = builtins.filter (d: isSubmoduleFn d.value) nonParametrics;
              paramFns = builtins.filter (d: !isSubmoduleFn d.value) nonParametrics;
            in
            if subFns != [ ] then
              at.merge loc subFns
            else
              let
                fn = (lib.last paramFns).value;
              in
              # Already-evaluated aspect attrsets pass through unchanged —
              # wrapping would destroy their includes and name. Only wrap
              # bare functions (raw lambdas) as parametric wrappers.
              if builtins.isAttrs fn then
                fn
              else
                let
                  args = lib.functionArgs fn;
                  nameFromLoc = lib.last loc;
                in
                {
                  name = nameFromLoc;
                  meta = {
                    provider = cnf.providerPrefix or [ ];
                  };
                  __fn = fn;
                  __args = args;
                  # Positional-arg providers (e.g. den.provides.user-shell)
                  # must remain callable so users can do (provider "arg").
                  __functor = self: self.__fn;
                }
          else
            at.merge loc nonParametrics;
    };

  aspectSubmodule =
    cnf:
    lib.types.submodule (
      { name, config, ... }:
      {
        freeformType = lib.types.lazyAttrsOf lib.types.deferredModule;
        imports = [
          (lib.mkAliasOptionModule [ "_" ] [ "provides" ])
          (den.schema.aspect or { })
        ];

        options = {
          name = lib.mkOption {
            description = "Aspect name";
            defaultText = lib.literalExpression "name";
            default = name;
            type = lib.types.str;
          };

          description = lib.mkOption {
            description = "Aspect description";
            defaultText = lib.literalExpression "name";
            default = "Aspect ${name}";
            type = lib.types.str;
          };

          meta = lib.mkOption {
            description = "Aspect attached meta data";
            type = lib.types.submodule {
              freeformType = lib.types.lazyAttrsOf lib.types.unspecified;
              config.self = config;
              options.handleWith = lib.mkOption {
                description = "Resolution handlers for this aspect's subtree";
                type = lib.types.nullOr (
                  lib.types.mkOptionType {
                    name = "handlerValue";
                    description = "handler record or list of handler records";
                    check = v: builtins.isAttrs v || builtins.isList v;
                    merge = _: defs: (lib.last defs).value;
                  }
                );
                default = null;
              };
              options.excludes = lib.mkOption {
                description = "Aspects to exclude from this subtree (sugar for handleWith)";
                type = lib.types.listOf lib.types.unspecified;
                default = [ ];
              };
              options.provider = lib.mkOption {
                internal = true;
                visible = false;
                description = "Provider path tracking aspect provenance";
                type = lib.types.listOf lib.types.str;
                default = cnf.providerPrefix or [ ];
              };
            };
            defaultText = lib.literalExpression "{ }";
            default = { };
          };

          includes = lib.mkOption {
            description = "Providers to ask aspects from";
            type = lib.types.listOf (providerType cnf);
            defaultText = lib.literalExpression "[ ]";
            default = [ ];
          };

          provides = lib.mkOption {
            description = "Providers of aspect for other aspects";
            defaultText = lib.literalExpression "{ }";
            default = { };
            type = lib.types.submodule {
              freeformType = lib.types.lazyAttrsOf (
                providerType (
                  cnf
                  // {
                    providerPrefix = (cnf.providerPrefix or [ ]) ++ [ config.name ];
                  }
                )
              );
            };
          };

        };
      }
    );

  # Coerce non-module functions to { includes = [fn]; } at the aspects level.
  # This is how { host, ... }: { nixos = ...; } becomes a proper aspect
  # with the function as a parametric include for the fx pipeline.
  coercedProviderType =
    cnf:
    let
      pt = providerType cnf;
    in
    lib.types.coercedTo (lib.types.addCheck lib.types.raw (
      v: builtins.isFunction v && !isSubmoduleFn v && lib.functionArgs v != { }
    )) (fn: { includes = [ fn ]; }) pt;

  aspectsType =
    cnf: lib.types.submodule { freeformType = lib.types.lazyAttrsOf (coercedProviderType cnf); };

in
{
  inherit
    aspectsType
    aspectType
    providerType
    parametricType
    isParametricWrapper
    ;
}
