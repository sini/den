# Tests for the structuredTrace adapter.
{ denTest, lib, ... }:
{
  flake.tests.structured-trace = {

    # structuredTrace produces flat entries with required fields.
    test-entry-fields = denTest (
      { den, ... }:
      let
        inherit (den.lib.aspects) adapters resolve;
        root = {
          name = "root";
          meta = {
            provider = [ ];
          };
          nixos = {
            a = 1;
          };
          includes = [
            {
              name = "child";
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
        result = resolve.withAdapter adapters.structuredTrace "nixos" root;
        entries = result.trace or [ ];
        rootEntry = builtins.head (builtins.filter (e: e.name == "root") entries);
      in
      {
        expr = {
          hasEntries = entries != [ ];
          rootHasClass = rootEntry.hasClass;
          rootClass = rootEntry.class;
          rootExcluded = rootEntry.excluded;
          hasChild = builtins.any (e: e.name == "child") entries;
        };
        expected = {
          hasEntries = true;
          rootHasClass = true;
          rootClass = "nixos";
          rootExcluded = false;
          hasChild = true;
        };
      }
    );

    # structuredTrace returns paths alongside entries.
    test-paths-collected = denTest (
      { den, ... }:
      let
        inherit (den.lib.aspects) adapters resolve;
        root = {
          name = "root";
          meta = {
            provider = [ ];
          };
          includes = [
            {
              name = "a";
              meta = {
                provider = [ ];
              };
              includes = [ ];
            }
            {
              name = "b";
              meta = {
                provider = [ ];
              };
              includes = [ ];
            }
          ];
        };
        result = resolve.withAdapter adapters.structuredTrace "nixos" root;
        pathKeys = map adapters.pathKey (result.paths or [ ]);
      in
      {
        expr = lib.sort (a: b: a < b) pathKeys;
        expected = [
          "a"
          "b"
          "root"
        ];
      }
    );

    # Excluded aspects appear in trace with excluded=true.
    test-excluded-in-trace = denTest (
      { den, ... }:
      let
        inherit (den.lib.aspects) adapters resolve;
        target = {
          name = "drop";
          meta = {
            provider = [ ];
          };
        };
        root = {
          name = "root";
          meta = {
            provider = [ ];
            adapter = adapters.excludeAspect target;
          };
          includes = [
            {
              name = "drop";
              meta = {
                provider = [ ];
              };
              includes = [ ];
            }
            {
              name = "keep";
              meta = {
                provider = [ ];
              };
              includes = [ ];
            }
          ];
        };
        result = resolve.withAdapter adapters.structuredTrace "nixos" root;
        excluded = builtins.filter (e: e.excluded) (result.trace or [ ]);
      in
      {
        expr = {
          hasExcluded = excluded != [ ];
          # structuredTrace uses meta.originalName ("drop"), not the ~prefixed tombstone name
          excludedName = if excluded != [ ] then (builtins.head excluded).name else "NONE";
        };
        expected = {
          hasExcluded = true;
          excludedName = "drop";
        };
      }
    );

    # Parent tracking: child entry has parent pointing to root.
    test-parent-tracking = denTest (
      { den, ... }:
      let
        inherit (den.lib.aspects) adapters resolve;
        root = {
          name = "root";
          meta = {
            provider = [ ];
          };
          includes = [
            {
              name = "child";
              meta = {
                provider = [ ];
              };
              includes = [ ];
            }
          ];
        };
        result = resolve.withAdapter adapters.structuredTrace "nixos" root;
        childEntry = builtins.head (builtins.filter (e: e.name == "child") (result.trace or [ ]));
      in
      {
        expr = childEntry.parent;
        expected = "root";
      }
    );

  };
}
