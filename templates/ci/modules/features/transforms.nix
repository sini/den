{ denTest, lib, ... }:
let
  transforms = import ../../../../nix/lib/aspects/transforms.nix { inherit lib; };
  inherit (transforms)
    normalizeResult
    id
    exclude
    substitute
    compose
    ;

  mkAspect = name: { inherit name; };
  mkProvider = name: provider: {
    inherit name;
    __provider = provider;
  };
  mkCtx = provided: {
    inherit provided;
    chain = [ ];
  };
in
{
  flake.tests.transforms = {

    test-normalizeResult-null = {
      expr = normalizeResult null;
      expected = {
        result = null;
      };
    };

    test-normalizeResult-attrset = {
      expr = normalizeResult { name = "foo"; };
      expected = {
        result = {
          name = "foo";
        };
      };
    };

    test-normalizeResult-rich = {
      expr = normalizeResult {
        result = {
          name = "foo";
        };
        trace = [ { x = 1; } ];
      };
      expected = {
        result = {
          name = "foo";
        };
      };
    };

    test-normalizeResult-rich-no-trace = {
      expr = normalizeResult {
        result = {
          name = "foo";
        };
      };
      expected = {
        result = {
          name = "foo";
        };
      };
    };

    test-id-passthrough = {
      expr = (id (mkCtx (mkAspect "foo"))).name;
      expected = "foo";
    };

    test-exclude-prunes-named = {
      expr = normalizeResult ((exclude [ (mkAspect "foo") ]) (mkCtx (mkAspect "foo")));
      expected = {
        result = null;
      };
    };

    test-exclude-passes-other = {
      expr = normalizeResult ((exclude [ (mkAspect "foo") ]) (mkCtx (mkAspect "bar")));
      expected = {
        result = {
          name = "bar";
        };
      };
    };

    test-exclude-passes-anonymous = {
      expr = normalizeResult (
        (exclude [ (mkAspect "foo") ]) (mkCtx {
          x = 1;
        })
      );
      expected = {
        result = {
          x = 1;
        };
      };
    };

    test-exclude-empty-list = {
      expr = normalizeResult ((exclude [ ]) (mkCtx (mkAspect "foo")));
      expected = {
        result = {
          name = "foo";
        };
      };
    };

    test-substitute-swaps-named = {
      expr = normalizeResult ((substitute (mkAspect "foo") (mkAspect "bar")) (mkCtx (mkAspect "foo")));
      expected = {
        result = {
          name = "bar";
        };
      };
    };

    test-substitute-passes-other = {
      expr = normalizeResult ((substitute (mkAspect "foo") (mkAspect "bar")) (mkCtx (mkAspect "baz")));
      expected = {
        result = {
          name = "baz";
        };
      };
    };

    test-substitute-passes-anonymous = {
      expr = normalizeResult (
        (substitute (mkAspect "foo") (mkAspect "bar")) (mkCtx {
          x = 1;
        })
      );
      expected = {
        result = {
          x = 1;
        };
      };
    };

    # aspect reference forms (attrset with .name)
    test-exclude-by-aspect-ref = {
      expr = normalizeResult ((exclude [ (mkAspect "foo") ]) (mkCtx (mkAspect "foo")));
      expected = {
        result = null;
      };
    };

    test-exclude-mixed-refs = {
      expr = normalizeResult (
        (exclude [
          (mkAspect "bar")
          (mkAspect "foo")
        ])
          (mkCtx (mkAspect "foo"))
      );
      expected = {
        result = null;
      };
    };

    test-substitute-by-aspect-ref = {
      expr = normalizeResult ((substitute (mkAspect "foo") (mkAspect "bar")) (mkCtx (mkAspect "foo")));
      expected = {
        result = {
          name = "bar";
        };
      };
    };

    test-compose-chains = {
      expr =
        compose
          [
            ({ provided, ... }: provided // { x = 1; })
            ({ provided, ... }: provided // { y = 2; })
          ]
          (mkCtx {
            name = "a";
          });
      expected = {
        name = "a";
        x = 1;
        y = 2;
      };
    };

    test-compose-shortcircuits-null = {
      expr =
        compose
          [
            ({ provided, ... }: null)
            ({ provided, ... }: provided // { y = 2; })
          ]
          (mkCtx {
            name = "a";
          });
      expected = null;
    };

    test-compose-empty-list = {
      expr = compose [ ] (mkCtx (mkAspect "a"));
      expected = {
        name = "a";
      };
    };

    # Provider-aware exclude: cascades to providers
    test-exclude-prunes-provider = {
      expr = normalizeResult (
        (exclude [ (mkAspect "monitoring") ]) (mkCtx (mkProvider "node-exporter" [ "monitoring" ]))
      );
      expected = {
        result = null;
      };
    };

    test-exclude-keeps-unrelated-provider = {
      expr = normalizeResult (
        (exclude [ (mkAspect "monitoring") ]) (mkCtx (mkProvider "node-exporter" [ "networking" ]))
      );
      expected = {
        result = {
          name = "node-exporter";
          __provider = [ "networking" ];
        };
      };
    };

    test-exclude-keeps-provider-when-not-excluded = {
      expr = normalizeResult (
        (exclude [ (mkAspect "tailscale") ]) (mkCtx (mkProvider "node-exporter" [ "monitoring" ]))
      );
      expected = {
        result = {
          name = "node-exporter";
          __provider = [ "monitoring" ];
        };
      };
    };

    # Deep cascade: exclude matches at any depth
    test-exclude-deep-cascade = {
      expr = normalizeResult (
        (exclude [ (mkAspect "monitoring") ]) (mkCtx {
          name = "collector";
          __provider = [
            "monitoring"
            "node-exporter"
          ];
        })
      );
      expected = {
        result = null;
      };
    };

    # Substitute cascades to providers
    test-substitute-cascade-with-provider = {
      expr =
        let
          replacement = {
            name = "mon-v2";
            provides.node-exporter = mkAspect "nex-v2";
          };
          r = (substitute (mkAspect "monitoring") replacement) (
            mkCtx (mkProvider "node-exporter" [ "monitoring" ])
          );
        in
        r.name;
      expected = "nex-v2";
    };

    # Substitute prunes when replacement lacks provider
    test-substitute-cascade-prunes-missing = {
      expr = normalizeResult (
        (substitute (mkAspect "monitoring") (mkAspect "mon-v2")) (
          mkCtx (mkProvider "node-exporter" [ "monitoring" ])
        )
      );
      expected = {
        result = null;
      };
    };

  };
}
