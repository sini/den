{
  denTest,
  inputs,
  lib,
  ...
}:
let
  fx = inputs.nix-effects.lib;
in
{
  flake.tests.fx-constraints = {

    test-exclude-declaration = denTest (
      { den, ... }:
      let
        fxLib = den.lib.aspects.fx.init fx;
        ref = {
          name = "drop";
          meta = {
            provider = [ ];
          };
        };
        decl = fxLib.exclude ref;
      in
      {
        expr = {
          type = decl.type;
          identity = decl.identity;
        };
        expected = {
          type = "exclude";
          identity = "drop";
        };
      }
    );

    test-substitute-declaration = denTest (
      { den, ... }:
      let
        fxLib = den.lib.aspects.fx.init fx;
        ref = {
          name = "old";
          meta = {
            provider = [ ];
          };
        };
        replacement = {
          name = "new";
          meta = {
            provider = [ ];
          };
          includes = [ ];
        };
        decl = fxLib.substitute ref replacement;
      in
      {
        expr = {
          type = decl.type;
          identity = decl.identity;
          replacementName = decl.replacementName;
        };
        expected = {
          type = "substitute";
          identity = "old";
          replacementName = "new";
        };
      }
    );

    test-exclude-via-registry = denTest (
      { den, ... }:
      let
        fxLib = den.lib.aspects.fx.init fx;
        ref = {
          name = "drop";
          meta = {
            provider = [ ];
          };
        };
        decl = fxLib.exclude ref;
        # Register then check-exclusion
        comp = fx.bind (fx.send "register-adapter" (decl // { owner = "test"; })) (
          _: fx.send "check-exclusion" "drop"
        );
        result = fx.handle {
          handlers = fxLib.handlers.adapterRegistryHandler;
          state = {
            adapterRegistry = { };
          };
        } comp;
      in
      {
        expr = result.value.action;
        expected = "exclude";
      }
    );

    test-check-exclusion-default-keep = denTest (
      { den, ... }:
      let
        fxLib = den.lib.aspects.fx.init fx;
        comp = fx.send "check-exclusion" "unknown";
        result = fx.handle {
          handlers = fxLib.handlers.adapterRegistryHandler;
          state = {
            adapterRegistry = { };
          };
        } comp;
      in
      {
        expr = result.value.action;
        expected = "keep";
      }
    );

    test-substitute-via-registry = denTest (
      { den, ... }:
      let
        fxLib = den.lib.aspects.fx.init fx;
        ref = {
          name = "old";
          meta = {
            provider = [ ];
          };
        };
        replacement = {
          name = "new";
          meta = {
            provider = [ ];
          };
          includes = [ ];
        };
        decl = fxLib.substitute ref replacement;
        comp = fx.bind (fx.send "register-adapter" (decl // { owner = "test"; })) (
          _: fx.send "check-exclusion" "old"
        );
        result = fx.handle {
          handlers = fxLib.handlers.adapterRegistryHandler;
          state = {
            adapterRegistry = { };
          };
        } comp;
      in
      {
        expr = {
          action = result.value.action;
          replacementName = result.value.replacement.name;
        };
        expected = {
          action = "substitute";
          replacementName = "new";
        };
      }
    );

    test-provideClassHandler-collects-imports = denTest (
      { den, ... }:
      let
        fxLib = den.lib.aspects.fx.init fx;
        parent = {
          name = "root";
          meta = { };
          includes = [
            {
              name = "a";
              meta = { };
              nixos = {
                enable = true;
              };
              includes = [ ];
            }
            {
              name = "b";
              meta = { };
              includes = [ ];
            }
          ];
        };
        comp = fxLib.resolve.resolveDeepEffectful {
          ctx = { };
          class = "nixos";
          aspect-chain = [ ];
        } parent;
        result = fx.handle {
          handlers = {
            "resolve-include" =
              { param, state }:
              {
                resume = param;
                inherit state;
              };
            "resolve-complete" =
              { param, state }:
              {
                resume = param;
                inherit state;
              };
            "check-exclusion" =
              { param, state }:
              {
                resume = {
                  action = "keep";
                };
                inherit state;
              };
          }
          // fxLib.handlers.provideClassHandler
          // fxLib.handlers.chainHandler;
          state = {
            imports = [ ];
            includesChain = [ ];
          };
        } comp;
      in
      {
        expr = builtins.length result.state.imports;
        expected = 1;
      }
    );

    test-collectPaths-excludes-tombstones = denTest (
      { den, ... }:
      let
        fxLib = den.lib.aspects.fx.init fx;
        target = {
          name = "drop";
          meta = {
            provider = [ ];
          };
        };
        parent = {
          name = "root";
          meta = {
            adapter = fxLib.exclude target;
          };
          includes = [
            {
              name = "keep";
              meta = {
                provider = [ ];
              };
              includes = [ ];
            }
            {
              name = "drop";
              meta = {
                provider = [ ];
              };
              includes = [ ];
            }
          ];
        };
        comp = fxLib.resolve.resolveDeepEffectful {
          ctx = { };
          class = "nixos";
          aspect-chain = [ ];
        } parent;
        result = fx.handle {
          handlers = {
            "resolve-include" =
              { param, state }:
              {
                resume = param;
                inherit state;
              };
          }
          // fxLib.handlers.adapterRegistryHandler
          // fxLib.identity.collectPathsHandler
          // fxLib.handlers.chainHandler;
          state = {
            paths = [ ];
            adapterRegistry = { };
            includesChain = [ ];
          };
        } comp;
      in
      {
        expr = builtins.length result.state.paths;
        expected = 1;
      }
    );

    test-exclude-default-scope = denTest (
      { den, ... }:
      let
        fxLib = den.lib.aspects.fx.init fx;
        ref = {
          name = "drop";
          meta.provider = [ ];
        };
        decl = fxLib.exclude ref;
      in
      {
        expr = decl.scope;
        expected = "subtree";
      }
    );

    test-exclude-global-scope = denTest (
      { den, ... }:
      let
        fxLib = den.lib.aspects.fx.init fx;
        ref = {
          name = "drop";
          meta.provider = [ ];
        };
        decl = fxLib.exclude.global ref;
      in
      {
        expr = {
          type = decl.type;
          scope = decl.scope;
          identity = decl.identity;
        };
        expected = {
          type = "exclude";
          scope = "global";
          identity = "drop";
        };
      }
    );

    test-substitute-default-scope = denTest (
      { den, ... }:
      let
        fxLib = den.lib.aspects.fx.init fx;
        ref = {
          name = "old";
          meta.provider = [ ];
        };
        replacement = {
          name = "new";
          meta.provider = [ ];
          includes = [ ];
        };
        decl = fxLib.substitute ref replacement;
      in
      {
        expr = decl.scope;
        expected = "subtree";
      }
    );

    test-substitute-global-scope = denTest (
      { den, ... }:
      let
        fxLib = den.lib.aspects.fx.init fx;
        ref = {
          name = "old";
          meta.provider = [ ];
        };
        replacement = {
          name = "new";
          meta.provider = [ ];
          includes = [ ];
        };
        decl = fxLib.substitute.global ref replacement;
      in
      {
        expr = decl.scope;
        expected = "global";
      }
    );

    test-filter-default-scope = denTest (
      { den, ... }:
      let
        fxLib = den.lib.aspects.fx.init fx;
        decl = fxLib.filterBy (_: true);
      in
      {
        expr = decl.scope;
        expected = "subtree";
      }
    );

    test-filter-global-scope = denTest (
      { den, ... }:
      let
        fxLib = den.lib.aspects.fx.init fx;
        decl = fxLib.filterBy.global (_: true);
      in
      {
        expr = decl.scope;
        expected = "global";
      }
    );

    test-scoped-exclude-in-subtree = denTest (
      { den, ... }:
      let
        fxLib = den.lib.aspects.fx.init fx;
        ref = {
          name = "drop";
          meta.provider = [ ];
        };
        decl = fxLib.exclude ref;
        comp = fx.bind (fx.send "chain-push" { identity = "parent"; }) (
          _:
          fx.bind (fx.send "register-adapter" (decl // { owner = "test"; })) (
            _:
            fx.bind (fx.send "chain-push" { identity = "child"; }) (
              _:
              fx.send "check-exclusion" {
                identity = "drop";
                aspect = null;
              }
            )
          )
        );
        result = fx.handle {
          handlers = fxLib.handlers.chainHandler // fxLib.handlers.adapterRegistryHandler;
          state = {
            includesChain = [ ];
            adapterRegistry = { };
            adapterFilters = [ ];
          };
        } comp;
      in
      {
        expr = result.value.action;
        expected = "exclude";
      }
    );

    test-scoped-exclude-outside-subtree = denTest (
      { den, ... }:
      let
        fxLib = den.lib.aspects.fx.init fx;
        ref = {
          name = "drop";
          meta.provider = [ ];
        };
        decl = fxLib.exclude ref;
        comp = fx.bind (fx.send "chain-push" { identity = "a"; }) (
          _:
          fx.bind (fx.send "register-adapter" (decl // { owner = "test"; })) (
            _:
            fx.bind (fx.send "chain-pop" null) (
              _:
              fx.bind (fx.send "chain-push" { identity = "b"; }) (
                _:
                fx.send "check-exclusion" {
                  identity = "drop";
                  aspect = null;
                }
              )
            )
          )
        );
        result = fx.handle {
          handlers = fxLib.handlers.chainHandler // fxLib.handlers.adapterRegistryHandler;
          state = {
            includesChain = [ ];
            adapterRegistry = { };
            adapterFilters = [ ];
          };
        } comp;
      in
      {
        expr = result.value.action;
        expected = "keep";
      }
    );

    test-global-exclude-ignores-chain = denTest (
      { den, ... }:
      let
        fxLib = den.lib.aspects.fx.init fx;
        ref = {
          name = "drop";
          meta.provider = [ ];
        };
        decl = fxLib.exclude.global ref;
        comp = fx.bind (fx.send "chain-push" { identity = "a"; }) (
          _:
          fx.bind (fx.send "register-adapter" (decl // { owner = "test"; })) (
            _:
            fx.bind (fx.send "chain-pop" null) (
              _:
              fx.bind (fx.send "chain-push" { identity = "b"; }) (
                _:
                fx.send "check-exclusion" {
                  identity = "drop";
                  aspect = null;
                }
              )
            )
          )
        );
        result = fx.handle {
          handlers = fxLib.handlers.chainHandler // fxLib.handlers.adapterRegistryHandler;
          state = {
            includesChain = [ ];
            adapterRegistry = { };
            adapterFilters = [ ];
          };
        } comp;
      in
      {
        expr = result.value.action;
        expected = "exclude";
      }
    );

    test-scoped-filter-in-subtree = denTest (
      { den, ... }:
      let
        fxLib = den.lib.aspects.fx.init fx;
        decl = fxLib.filterBy (a: a.name != "drop");
        aspect = {
          name = "drop";
          meta.provider = [ ];
        };
        comp = fx.bind (fx.send "chain-push" { identity = "parent"; }) (
          _:
          fx.bind (fx.send "register-adapter" (decl // { owner = "test"; })) (
            _:
            fx.send "check-exclusion" {
              identity = "drop";
              inherit aspect;
            }
          )
        );
        result = fx.handle {
          handlers = fxLib.handlers.chainHandler // fxLib.handlers.adapterRegistryHandler;
          state = {
            includesChain = [ ];
            adapterRegistry = { };
            adapterFilters = [ ];
          };
        } comp;
      in
      {
        expr = result.value.action;
        expected = "exclude";
      }
    );

    test-scoped-filter-outside-subtree = denTest (
      { den, ... }:
      let
        fxLib = den.lib.aspects.fx.init fx;
        decl = fxLib.filterBy (a: a.name != "drop");
        aspect = {
          name = "drop";
          meta.provider = [ ];
        };
        comp = fx.bind (fx.send "chain-push" { identity = "a"; }) (
          _:
          fx.bind (fx.send "register-adapter" (decl // { owner = "test"; })) (
            _:
            fx.bind (fx.send "chain-pop" null) (
              _:
              fx.bind (fx.send "chain-push" { identity = "b"; }) (
                _:
                fx.send "check-exclusion" {
                  identity = "drop";
                  inherit aspect;
                }
              )
            )
          )
        );
        result = fx.handle {
          handlers = fxLib.handlers.chainHandler // fxLib.handlers.adapterRegistryHandler;
          state = {
            includesChain = [ ];
            adapterRegistry = { };
            adapterFilters = [ ];
          };
        } comp;
      in
      {
        expr = result.value.action;
        expected = "keep";
      }
    );

    test-provideClassHandler-skips-tombstones = denTest (
      { den, ... }:
      let
        fxLib = den.lib.aspects.fx.init fx;
        target = {
          name = "drop";
          meta = {
            provider = [ ];
          };
        };
        parent = {
          name = "root";
          meta = {
            adapter = fxLib.exclude target;
          };
          includes = [
            {
              name = "keep";
              meta = {
                provider = [ ];
              };
              nixos = {
                a = 1;
              };
              includes = [ ];
            }
            {
              name = "drop";
              meta = {
                provider = [ ];
              };
              nixos = {
                b = 2;
              };
              includes = [ ];
            }
          ];
        };
        comp = fxLib.resolve.resolveDeepEffectful {
          ctx = { };
          class = "nixos";
          aspect-chain = [ ];
        } parent;
        result = fx.handle {
          handlers = {
            "resolve-include" =
              { param, state }:
              {
                resume = param;
                inherit state;
              };
            "resolve-complete" =
              { param, state }:
              {
                resume = param;
                inherit state;
              };
          }
          // fxLib.handlers.adapterRegistryHandler
          // fxLib.handlers.provideClassHandler
          // fxLib.handlers.chainHandler;
          state = {
            imports = [ ];
            adapterRegistry = { };
            includesChain = [ ];
          };
        } comp;
      in
      {
        expr = builtins.length result.state.imports;
        expected = 1;
      }
    );

  };
}
