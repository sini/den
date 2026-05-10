# Effect handler: emit-class
# Collects class modules into scope-partitioned buckets with dedup.
{ den, ... }:
let
  classCollectorHandler = {
    "emit-class" =
      { param, state }:
      let
        nodeIdentity = param.identity or "<anon>";
        isRawEntry = param.__rawEntry or false;
        baseIdentity =
          if param.isContextDependent or false then
            nodeIdentity
          else
            den.lib.aspects.fx.identity.stripCtxSuffix nodeIdentity;
        loc = "${param.class}@${baseIdentity}";
        mod =
          if isRawEntry then
            param // { __loc = loc; }
          else if den.lib.aspects.fx.identity.isAnonIdentity nodeIdentity then
            den.lib.setDefaultModuleLocation loc param.module
          else
            {
              key = loc;
              _file = loc;
              imports = [ param.module ];
            };
        scope = state.currentScope;
        emittedLocs = (state.scopedEmittedLocs or (_: { })) null;
        scopeLocs = emittedLocs.${scope} or { };
        alreadyEmitted = scopeLocs ? ${loc};
      in
      {
        resume = builtins.trace "EMIT: class=${param.class} loc=${loc} scope=${scope} dup=${builtins.toJSON alreadyEmitted}" null;
        state =
          if alreadyEmitted then
            builtins.trace "DEDUP: pruned ${loc} in scope ${scope}" state
          else
            state
            // {
              scopedClassImports =
                x:
                let
                  all = state.scopedClassImports x;
                  scopeData = all.${scope} or { };
                in
                all
                // {
                  ${scope} = scopeData // {
                    ${param.class} = (scopeData.${param.class} or [ ]) ++ [ mod ];
                  };
                };
              scopedEmittedLocs =
                _:
                emittedLocs
                // {
                  ${scope} = scopeLocs // {
                    ${loc} = true;
                  };
                };
            };
      };
  };
in
{
  inherit classCollectorHandler;
}
