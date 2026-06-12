# Resolve gen-schema the same way fx.nix resolves nix-effects: prefer the
# consumer-provided flake input, fall back to the rev pinned in the CI lock so
# den evaluates without forcing every consumer to declare the input.
{ inputs, lib, ... }:
let
  lock = builtins.fromJSON (builtins.readFile ../../templates/ci/flake.lock);
  locked = lock.nodes.gen-schema.locked;
  gen-schema = builtins.fetchTarball {
    url = "https://github.com/${locked.owner}/${locked.repo}/archive/${locked.rev}.zip";
    sha256 = locked.narHash;
  };
in
inputs.gen-schema.lib or (import gen-schema { inherit lib; })
