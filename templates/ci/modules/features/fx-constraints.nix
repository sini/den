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
        # Register then check-constraint
        comp = fx.bind (fx.send "register-constraint" (decl // { owner = "test"; })) (
          _: fx.send "check-constraint" "drop"
        );
        result = fx.handle {
          handlers = fxLib.handlers.constraintRegistryHandler;
          state = {
            constraintRegistry = { };
          };
        } comp;
      in
      {
        expr = result.value.action;
        expected = "exclude";
      }
    );

    test-check-constraint-default-keep = denTest (
      { den, ... }:
      let
        fxLib = den.lib.aspects.fx.init fx;
        comp = fx.send "check-constraint" "unknown";
        result = fx.handle {
          handlers = fxLib.handlers.constraintRegistryHandler;
          state = {
            constraintRegistry = { };
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
        comp = fx.bind (fx.send "register-constraint" (decl // { owner = "test"; })) (
          _: fx.send "check-constraint" "old"
        );
        result = fx.handle {
          handlers = fxLib.handlers.constraintRegistryHandler;
          state = {
            constraintRegistry = { };
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
            "check-constraint" =
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
            handleWith = fxLib.exclude target;
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
          // fxLib.handlers.constraintRegistryHandler
          // fxLib.identity.collectPathsHandler
          // fxLib.handlers.chainHandler;
          state = {
            paths = [ ];
            constraintRegistry = { };
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
          fx.bind (fx.send "register-constraint" (decl // { owner = "test"; })) (
            _:
            fx.bind (fx.send "chain-push" { identity = "child"; }) (
              _:
              fx.send "check-constraint" {
                identity = "drop";
                aspect = null;
              }
            )
          )
        );
        result = fx.handle {
          handlers = fxLib.handlers.chainHandler // fxLib.handlers.constraintRegistryHandler;
          state = {
            includesChain = [ ];
            constraintRegistry = { };
            constraintFilters = [ ];
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
          fx.bind (fx.send "register-constraint" (decl // { owner = "test"; })) (
            _:
            fx.bind (fx.send "chain-pop" null) (
              _:
              fx.bind (fx.send "chain-push" { identity = "b"; }) (
                _:
                fx.send "check-constraint" {
                  identity = "drop";
                  aspect = null;
                }
              )
            )
          )
        );
        result = fx.handle {
          handlers = fxLib.handlers.chainHandler // fxLib.handlers.constraintRegistryHandler;
          state = {
            includesChain = [ ];
            constraintRegistry = { };
            constraintFilters = [ ];
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
          fx.bind (fx.send "register-constraint" (decl // { owner = "test"; })) (
            _:
            fx.bind (fx.send "chain-pop" null) (
              _:
              fx.bind (fx.send "chain-push" { identity = "b"; }) (
                _:
                fx.send "check-constraint" {
                  identity = "drop";
                  aspect = null;
                }
              )
            )
          )
        );
        result = fx.handle {
          handlers = fxLib.handlers.chainHandler // fxLib.handlers.constraintRegistryHandler;
          state = {
            includesChain = [ ];
            constraintRegistry = { };
            constraintFilters = [ ];
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
          fx.bind (fx.send "register-constraint" (decl // { owner = "test"; })) (
            _:
            fx.send "check-constraint" {
              identity = "drop";
              inherit aspect;
            }
          )
        );
        result = fx.handle {
          handlers = fxLib.handlers.chainHandler // fxLib.handlers.constraintRegistryHandler;
          state = {
            includesChain = [ ];
            constraintRegistry = { };
            constraintFilters = [ ];
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
          fx.bind (fx.send "register-constraint" (decl // { owner = "test"; })) (
            _:
            fx.bind (fx.send "chain-pop" null) (
              _:
              fx.bind (fx.send "chain-push" { identity = "b"; }) (
                _:
                fx.send "check-constraint" {
                  identity = "drop";
                  inherit aspect;
                }
              )
            )
          )
        );
        result = fx.handle {
          handlers = fxLib.handlers.chainHandler // fxLib.handlers.constraintRegistryHandler;
          state = {
            includesChain = [ ];
            constraintRegistry = { };
            constraintFilters = [ ];
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
            handleWith = fxLib.exclude target;
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
          // fxLib.handlers.constraintRegistryHandler
          // fxLib.handlers.provideClassHandler
          // fxLib.handlers.chainHandler;
          state = {
            imports = [ ];
            constraintRegistry = { };
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
