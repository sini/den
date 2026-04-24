# constantHandler: Handles <arg-name> effects — resumes with context values for parametric aspects.
# ctxSeenHandler: Handles ctx-seen — dedup tracking for context stages.
# State reads: seen | State writes: seen
{
  lib,
  den,
  ...
}:
let
  # Build handler set from context.
  # Each key in ctx becomes a handler that resumes with the value.
  # has-handler queries the handler scope directly, including scoped
  # handlers from scope.provide.
  constantHandler =
    ctx:
    builtins.mapAttrs (
      _: value:
      { param, state }:
      {
        resume = value;
        inherit state;
      }
    ) ctx;

  # Dedup handler. Tracks seen keys in state.seen.
  ctxSeenHandler = {
    "ctx-seen" =
      { param, state }:
      let
        seenSet = (state.seen or (_: { })) null;
        isFirst = !(seenSet ? ${param});
      in
      {
        resume = { inherit isFirst; };
        state = state // {
          seen = _: seenSet // { ${param} = true; };
        };
      };
  };

in
{
  inherit
    constantHandler
    ctxSeenHandler
    ;
}
