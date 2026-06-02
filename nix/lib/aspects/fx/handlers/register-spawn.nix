# Effect handler: register-spawn
# Collects deferred node spawn requests into scopedSpawns. The drain
# augmentation in resolve.nix materializes them post-walk over the parent
# pipeline's full scope-tree state.
_:
let
  inherit (import ./state-util.nix) scopedAppend;

  registerSpawnHandler = {
    "register-spawn" =
      { param, state }:
      let
        scope = state.currentScope;
      in
      {
        resume = null;
        state = scopedAppend state "scopedSpawns" scope (param // { sourceScopeId = scope; });
      };
  };
in
{
  inherit registerSpawnHandler;
}
