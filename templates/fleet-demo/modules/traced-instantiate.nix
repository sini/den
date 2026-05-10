# Demo: module-hook — inject virtual args into NixOS modules via lib.evalModules.
#
# This module wires the module-hook library to den's host instantiation,
# overriding `den.schema.host.instantiate` with a hooked `nixosSystem`.
# The hook intercepts module functions at the evalModules boundary,
# injecting virtual arguments by wrapping functions and stripping the
# virtual args from their signature before the NixOS module system sees them.
#
# Technique:
#   - lib.evalModules is overridden via lib.extend to wrap the modules list
#   - extendModules on the result is also wrapped (eval-config.nix uses it)
#   - Function modules requesting virtual args get them partially applied
#   - Only public nixpkgs APIs are used (lib.evalModules, lib.setFunctionArgs)
#
# Findings:
#   - Direct module injection at the instantiate boundary works perfectly.
#     Modules added to the `modules` list receive virtual args transparently.
#   - Den aspects go through den's wrapClassModule before reaching the hook.
#     Den's wrapping re-advertises all function args (including virtual ones)
#     to the NixOS module system, which then tries to resolve them from
#     _module.args. This means den aspects need den-level integration for
#     virtual arg injection — the hook alone isn't sufficient for deep modules.
#   - For non-den configurations (bare flake-parts, import-tree, etc.),
#     the hook works at all depths via recursive import wrapping.
#
# Run:
#   nix eval --override-input den . \
#     ./templates/fleet-demo#nixosConfigurations.lb-prod.config.environment.etc.den-hook-demo.text
#
# Expected output:
#   module-hook proof of concept
#   ---
#   Greeting:       hello from module-hook
#   Virtual host:   injected-during-eval
#   NixOS hostname: lb-prod
{ inputs, lib, ... }:
let
  moduleHook = import ./_module-hook { inherit lib; };

  hookedNixosSystem = moduleHook.mkHookedNixosSystem inputs.nixpkgs {
    trace = true;
    virtualArgs = {
      # In a real integration these would carry entity context from
      # den's schema system — different values per host evaluation.
      den-context = {
        greeting = "hello from module-hook";
        host-name = "injected-during-eval";
      };
    };
  };

  # A bare NixOS module that takes `den-context` as a function arg.
  # The hook wraps it: strips `den-context` from the signature, injects
  # the value. The NixOS module system only sees `{ config, ... }:`.
  demoModule =
    { den-context, config, ... }:
    {
      _file = "traced-instantiate.nix#demoModule";
      environment.etc."den-hook-demo".text = ''
        module-hook proof of concept
        ---
        Greeting:       ${den-context.greeting}
        Virtual host:   ${den-context.host-name}
        NixOS hostname: ${config.networking.hostName}
      '';
    };

in
{
  den.schema.host.instantiate = lib.mkDefault (
    args:
    hookedNixosSystem (
      args
      // {
        modules = (args.modules or [ ]) ++ [ demoModule ];
      }
    )
  );
}
