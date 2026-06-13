# instantiate.nix — the flake-output T-arm edge constructor (spec §2: T = a
# flake-output path). An instantiate spec delivers a host/home's collected class
# content to a flake-output attrpath (nixosConfigurations.<name>, etc.). Unlike
# the entity-root T-arm (default fold / routes / provides), the flake-output arm
# carries its OWN edge-construction rules — notably @system disambiguation for
# colliding output names — which are T-arm-LOCAL, never general materializer
# steps (spec §2 "the flake-output arm carries its own edge-construction rules").
#
# Both the read-only oracle (edge-trace.nix) and production (resolve.nix
# applyInstantiates) source their flake-output descriptors from HERE, so they can
# never disagree on the @system rule (spec §3a convergence). Production maps the
# disambiguated descriptors to lazy instantiate thunks; the oracle maps them to
# edge records. Neither path touches spec.instantiate — only path + system
# metadata — so the descriptor build is laziness-safe (the thunk tree the
# materializer builds, resolve.nix:instantiateConfigs, is what forces instantiate
# on output ACCESS).
{ lib, ... }:
let
  # spec → output descriptor { path; system; spec }, or [] when the spec has no
  # output (intoAttr empty). path = [ "flake" ] ++ intoAttr.
  specDescriptor =
    spec:
    let
      hasOutput = (spec.intoAttr or [ ]) != [ ];
    in
    if !hasOutput then
      [ ]
    else
      [
        {
          path = [ "flake" ] ++ spec.intoAttr;
          system = spec.system or null;
          inherit spec;
        }
      ];

  # All output descriptors for a flat instantiate-spec list.
  specDescriptors = specs: lib.concatMap specDescriptor specs;

  # @system disambiguation (the T-arm-local rule). Entries colliding on the same
  # output path are resolved:
  #   - DIFFERENT systems  → qualify each output name with @system so both are
  #     accessible (e.g. homeConfigurations."ben@x86_64-linux"). Without this,
  #     lib.recursiveUpdate would deep-merge two independent module-system
  #     evaluations and corrupt both.
  #   - SAME entity via multiple policy paths (e.g. fleet + direct) → dedup,
  #     keeping the last (lib.warn on collision). The kept modules are compatible.
  #
  # Returns the disambiguated descriptor list (path possibly @system-qualified).
  # Inspects path + system metadata ONLY — never spec.instantiate (laziness-safe).
  disambiguate =
    descriptors:
    let
      pathStr = builtins.concatStringsSep ".";
      grouped = builtins.foldl' (
        acc: entry:
        let
          key = pathStr entry.path;
        in
        acc // { ${key} = (acc.${key} or [ ]) ++ [ entry ]; }
      ) { } descriptors;
      resolveGroup =
        _: entries:
        if builtins.length entries <= 1 then
          entries
        else
          let
            systems = map (e: e.system or null) entries;
            uniqueSystems = lib.unique systems;
            isMultiSystem = builtins.length uniqueSystems > 1;
          in
          if isMultiSystem then
            map (
              e:
              let
                basePath = lib.init e.path;
                baseName = lib.last e.path;
              in
              e // { path = basePath ++ [ "${baseName}@${e.system}" ]; }
            ) entries
          else
            let
              entry = lib.last entries;
            in
            lib.warnIf (builtins.length entries > 1)
              "den: multiple instantiate specs target ${builtins.concatStringsSep "." entry.path} on ${
                if entry.system != null then entry.system else "unknown"
              }; keeping last"
              [ entry ];
    in
    lib.concatLists (lib.mapAttrsToList resolveGroup grouped);
in
{
  inherit specDescriptors disambiguate;
}
