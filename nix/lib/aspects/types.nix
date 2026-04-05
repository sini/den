{ lib, den, ... }:
let
  inherit (den.lib) lastFunctionTo;

  wrapProvider =
    parentPath: val:
    if builtins.isFunction val then
      {
        __provider = parentPath;
        __functor = self: arg: wrapProvider self.__provider (val arg);
        __functionArgs = lib.functionArgs val;
      }
    else if builtins.isAttrs val then
      val // { __provider = parentPath; }
    else
      val;

  isSubmoduleFn =
    m:
    let
      args = lib.functionArgs m;
    in
    builtins.any (k: args ? ${k}) [
      "lib"
      "config"
      "options"
      "aspect"
    ];

  providerArgNames = [
    "aspect-chain"
    "class"
  ];

  isProviderFn =
    f:
    let
      names = builtins.attrNames (lib.functionArgs f);
    in
    names != [ ] && builtins.all (n: builtins.elem n providerArgNames) names;

  directProviderFn = cnf: lib.types.addCheck (lastFunctionTo (aspectSubmodule cnf)) isProviderFn;

  curriedProviderFn =
    cnf:
    lib.types.addCheck (lastFunctionTo (providerType cnf)) (
      f:
      builtins.isFunction f
      ||
        builtins.isAttrs f
        &&
          builtins.removeAttrs f [
            "__functor"
            "__functionArgs"
            "__provider"
          ] == { }
    );

  providerFn = cnf: lib.types.either (directProviderFn cnf) (curriedProviderFn cnf);

  providerType = cnf: lib.types.either (providerFn cnf) (aspectSubmodule cnf);

  aspectSubmodule =
    cnf:
    lib.types.submodule (
      { name, config, ... }:
      {
        freeformType = lib.types.lazyAttrsOf lib.types.deferredModule;
        config._module.args.aspect = config;
        imports = [ (lib.mkAliasOptionModule [ "_" ] [ "provides" ]) ];

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

          includes = lib.mkOption {
            description = "Providers to ask aspects from";
            type = lib.types.listOf (providerType cnf);
            defaultText = lib.literalExpression "[ ]";
            default = [ ];
          };

          excludes = lib.mkOption {
            description = "Aspects to exclude from this aspect's include subtree";
            type = lib.types.listOf lib.types.raw;
            default = [ ];
          };

          transforms = lib.mkOption {
            description = "Transform functions applied during resolution of this aspect's subtree";
            type = lib.types.listOf lib.types.raw;
            default = [ ];
          };

          provides =
            let
              base = if config.__provider or [ ] != [ ] then config.__provider else cnf.providerPrefix or [ ];
              parentPath = base ++ [ name ];
              childCnf = cnf // {
                providerPrefix = parentPath;
              };
            in
            lib.mkOption {
              description = "Providers of aspect for other aspects";
              defaultText = lib.literalExpression "{ }";
              default = { };
              type = lib.types.submodule (
                { config, ... }:
                {
                  freeformType = lib.types.lazyAttrsOf (providerType childCnf);
                  config._module.args.aspects = config;
                }
              );
              apply = lib.mapAttrs (_: wrapProvider parentPath);
            };

          __provider = lib.mkOption {
            internal = true;
            visible = false;
            description = "Provider origin path";
            type = lib.types.listOf lib.types.str;
            default = cnf.providerPrefix or [ ];
          };

          __functor = lib.mkOption {
            internal = true;
            visible = false;
            description = "Functor to default provider";
            type = lastFunctionTo (providerType cnf);
            defaultText = lib.literalExpression "lib.const";
            default = cnf.defaultFunctor or lib.const;
          };
        };
      }
    );

  aspectsType =
    cnf:
    lib.types.submodule (
      { config, ... }:
      {
        freeformType = lib.types.lazyAttrsOf (
          lib.types.either (lib.types.addCheck (aspectSubmodule cnf) (
            m: (!builtins.isFunction m) || isSubmoduleFn m
          )) (providerType cnf)
        );
        config._module.args.aspects = config;
      }
    );

in
{
  inherit aspectsType aspectSubmodule providerType;
}
