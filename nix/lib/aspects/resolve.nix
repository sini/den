{ lib, ... }:
let
  inherit (import ./transforms.nix { inherit lib; }) exclude compose;

  resolveWith =
    class: opts: aspect-chain: aspect:
    let
      rawExcludes = aspect.excludes or [ ];
      rawTransforms = aspect.transforms or [ ];

      provided = if lib.isFunction aspect then aspect { inherit class aspect-chain; } else aspect;

      inheritedTransforms = opts.transforms or [ ];
      composed = if inheritedTransforms == [ ] then null else compose inheritedTransforms;

      result =
        if composed != null then
          composed {
            inherit provided class;
            chain = aspect-chain;
          }
        else
          provided;

      # Build trace entries directly — no functor wrapper, no extra call depth
      doTrace = opts.trace or false;
      aspectName = provided.name or "<anon>";
      resultName = if result != null then (result.name or "<anon>") else null;
      decision =
        if result == null then
          "pruned"
        else if resultName != aspectName then
          "replaced"
        else
          "included";
      providerPath = provided.__provider or [ ];
      traceEntry = {
        name = aspectName;
        inherit class decision;
        depth = builtins.length aspect-chain;
        chain = map (a: a.name or "<anon>") aspect-chain;
      }
      // lib.optionalAttrs (decision == "replaced") { replacedBy = resultName; }
      // lib.optionalAttrs (providerPath != [ ]) { provider = providerPath; };
      traceEntries = if doTrace then [ traceEntry ] else [ ];
    in
    if result == null then
      {
        imports = [ ];
        trace = traceEntries;
      }
    else
      let
        walked = result;
        allExcludes = lib.unique ((walked.excludes or [ ]) ++ rawExcludes);
        excludeTransforms = lib.optional (allExcludes != [ ]) (exclude allExcludes);
        childOpts = opts // {
          transforms = excludeTransforms ++ rawTransforms ++ (opts.transforms or [ ]);
        };
        next-chain = aspect-chain ++ [ walked ];
        children = map (resolveWith class childOpts next-chain) (walked.includes or [ ]);
        forwardTrace = if doTrace then walked.__forwardTrace or [ ] else [ ];
      in
      {
        imports =
          (lib.optional (walked ? ${class}) walked.${class}) ++ (map (c: { inherit (c) imports; }) children);
        trace = traceEntries ++ forwardTrace ++ (lib.concatMap (c: c.trace) children);
      };

  defaultOpts = {
    transforms = [ ];
    trace = false;
  };

  resolve =
    class: aspect:
    let
      r = resolveWith class defaultOpts [ ] aspect;
    in
    {
      inherit (r) imports;
    };

  resolve' =
    class: opts: aspect:
    let
      r = resolveWith class opts [ ] aspect;
    in
    {
      module = { inherit (r) imports; };
      inherit (r) trace;
    };

in
{
  inherit resolve resolve';
}
