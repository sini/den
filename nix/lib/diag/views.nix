# Standard view definitions for aspect-resolution diagrams.
#
# Each view is a record describing what to compute from a graph IR
# and how to present it. Views are returned as lists so templates can
# extend (`++ [ myView ]`), filter (`builtins.filter`), or replace
# individual entries.
#
# Usage from a template:
#
#   rc = diag.renderContext { inherit pkgs theme; mermaidConfig = elkCfg; };
#   hostViewDefs = diag.views.host rc;
#
#   # Extend with a custom view:
#   hostViewDefs = (diag.views.host rc) ++ [ myCustomView ];
#
#   # Drop a view:
#   hostViewDefs = builtins.filter (v: v.view != "pipeline")
#     (diag.views.host rc);
#
# Fields per view entry:
#
#   view      — short identifier (used in file name: `<entity>-<view>.md`)
#   title     — markdown heading
#   altText   — SVG alt text
#   mdLang    — fenced code block language (`mermaid`, `plantuml`, `json`)
#   svgInfix  — `mmd`/`puml`/`dot`/null; inserted before `.svg` in filename
#   svgFn     — base → source → derivation (null = no SVG render)
#   compute   — graph → source string
#
{ graph, toJSON }:
let
  mmd = svgFn: {
    mdLang = "mermaid";
    svgInfix = "mmd";
    inherit svgFn;
  };
  puml = svgFn: {
    mdLang = "plantuml";
    svgInfix = "puml";
    inherit svgFn;
  };
  json = {
    mdLang = "json";
    svgInfix = null;
    svgFn = null;
  };

  # mkView — canonical constructor for a single view entry.
  #
  # view    — short identifier
  # title   — markdown heading / SVG alt text (altText defaults to title)
  # altText — override SVG alt text when it differs from title
  # fmt     — mmd/puml/json format attrs (from helpers above)
  # compute — graph → source string
  mkView =
    {
      view,
      title,
      altText ? title,
      fmt,
      compute,
    }:
    {
      inherit
        view
        title
        altText
        compute
        ;
    }
    // fmt;

  self = {

    # --- Entity-agnostic core views (14) ---
    #
    # Shared foundation for every entity kind (host, user, home, …).
    core =
      {
        render,
        renderDense,
        mmdSourceToSvg,
        pumlSourceToSvg,
        ...
      }:
      [
        (mkView {
          view = "ctx";
          title = "Context Hierarchy";
          altText = "Context hierarchy";
          fmt = mmd mmdSourceToSvg;
          compute = g: renderDense.toMermaid (graph.contextOnly g);
        })

        (mkView {
          view = "aspects";
          title = "Aspect Hierarchy";
          altText = "Aspect hierarchy";
          fmt = mmd mmdSourceToSvg;
          compute = g: renderDense.toMermaid (graph.aspectsOnly g);
        })

        (mkView {
          view = "simple";
          title = "Simplified View";
          altText = "Simplified";
          fmt = mmd mmdSourceToSvg;
          compute = g: renderDense.toMermaid (graph.simplified g);
        })

        (mkView {
          view = "seq";
          title = "Resolution Sequence";
          altText = "Sequence";
          fmt = mmd mmdSourceToSvg;
          compute = g: render.toSequenceMermaid g;
        })

        (mkView {
          view = "seq-full";
          title = "Resolution Sequence (expanded)";
          altText = "Sequence expanded";
          fmt = mmd mmdSourceToSvg;
          compute = g: render.toSequenceMermaidExpanded g;
        })

        (mkView {
          view = "providers";
          title = "Provider Tree";
          altText = "Providers";
          fmt = mmd mmdSourceToSvg;
          compute = g: renderDense.toMermaid (graph.providersOnly g);
        })

        (mkView {
          view = "adapters";
          title = "Adapter Impact";
          altText = "Adapters";
          fmt = mmd mmdSourceToSvg;
          compute = g: renderDense.toMermaid (graph.adaptersOnly g);
        })

        (mkView {
          view = "decisions";
          title = "Structural Decisions";
          altText = "Decisions";
          fmt = mmd mmdSourceToSvg;
          compute = g: renderDense.toMermaid (graph.decisionsView g);
        })

        (mkView {
          view = "parametric";
          title = "Parametric Aspects";
          altText = "Parametric";
          fmt = mmd mmdSourceToSvg;
          compute = g: renderDense.toMermaid (graph.parametricOnly g);
        })

        (mkView {
          view = "declared";
          title = "User-Declared Aspects";
          altText = "Declared";
          fmt = mmd mmdSourceToSvg;
          compute = g: renderDense.toMermaid (graph.userDeclaredOnly g);
        })

        (mkView {
          view = "orphans";
          title = "Orphans and Leaves";
          altText = "Orphans and leaves";
          fmt = mmd mmdSourceToSvg;
          compute = g: renderDense.toMermaid (graph.orphansAndLeaves g);
        })

        (mkView {
          view = "pipeline";
          title = "Resolution Pipeline (machinery)";
          altText = "Pipeline";
          fmt = mmd mmdSourceToSvg;
          compute = g: renderDense.toMermaid (graph.pipelineOnly g);
        })

        (mkView {
          view = "state";
          title = "Context State Diagram";
          altText = "State";
          fmt = mmd mmdSourceToSvg;
          compute = g: render.toStateMermaid (graph.contextOnly g);
        })

        (mkView {
          view = "ir";
          title = "Graph IR (JSON)";
          altText = "IR JSON";
          fmt = json;
          compute = g: toJSON g;
        })
      ];

    # --- Shared homeManager views (user + home) ---
    #
    # Both user and home entities expose identical hm-scoped views.
    hmViews =
      {
        renderDense,
        mmdSourceToSvg,
        ...
      }:
      [
        (mkView {
          view = "has-aspect-hm";
          title = "hasAspect Presence: homeManager";
          altText = "hasAspect homeManager";
          fmt = mmd mmdSourceToSvg;
          compute = g: renderDense.toMermaid (graph.hasAspectPresent { class = "homeManager"; } g);
        })

        (mkView {
          view = "class-hm";
          title = "Class Slice: homeManager";
          altText = "homeManager slice";
          fmt = mmd mmdSourceToSvg;
          compute = g: renderDense.toMermaid (graph.classSlice "homeManager" g);
        })
      ];

    # --- Per-entity views (host): core + host-specific (~28) ---
    host =
      rc@{
        render,
        renderDense,
        mmdSourceToSvg,
        pumlSourceToSvg,
        ...
      }:
      (self.core rc)
      ++ (self.hmViews rc)
      ++ [
        (mkView {
          view = "has-aspect-nixos";
          title = "hasAspect Presence: nixos";
          altText = "hasAspect nixos";
          fmt = mmd mmdSourceToSvg;
          compute = g: renderDense.toMermaid (graph.hasAspectPresent { class = "nixos"; } g);
        })

        (mkView {
          view = "class-nixos";
          title = "Class Slice: nixos";
          altText = "nixos slice";
          fmt = mmd mmdSourceToSvg;
          compute = g: renderDense.toMermaid (graph.classSlice "nixos" g);
        })

        (mkView {
          view = "cross-class";
          title = "Cross-Class Aspects";
          altText = "Cross-class";
          fmt = mmd mmdSourceToSvg;
          compute = g: renderDense.toMermaid (graph.crossClassOnly g);
        })

        (mkView {
          view = "diff-classes";
          title = "Class Diff (nixos vs homeManager)";
          altText = "Class diff";
          fmt = mmd mmdSourceToSvg;
          compute =
            g:
            renderDense.toMermaid (
              graph.diff {
                a = graph.classSlice "nixos" g;
                b = graph.classSlice "homeManager" g;
              }
            );
        })

        (mkView {
          view = "sankey";
          title = "Sankey Flow";
          altText = "Sankey";
          fmt = mmd mmdSourceToSvg;
          compute = g: render.toSankeyMermaid (graph.simplified g);
        })

        (mkView {
          view = "treemap";
          title = "Treemap";
          fmt = mmd mmdSourceToSvg;
          compute = g: render.toTreemapMermaid g;
        })

        (mkView {
          view = "mindmap";
          title = "Provider Mindmap";
          altText = "Mindmap";
          fmt = mmd mmdSourceToSvg;
          compute = g: render.toMindmapMermaid (graph.providersOnly g);
        })

        (mkView {
          view = "fan";
          title = "Fan-In / Fan-Out";
          altText = "Fan metrics";
          fmt = mmd mmdSourceToSvg;
          compute =
            g:
            render.toFanMetricsSankey {
              rootName = g.rootName;
              metrics = graph.fanMetrics g;
            };
        })

        (mkView {
          view = "c4container";
          title = "C4 Container View";
          altText = "C4 Container";
          fmt = puml pumlSourceToSvg;
          compute = g: render.toC4Container g;
        })

        (mkView {
          view = "c4component";
          title = "C4 Component View";
          altText = "C4 Component";
          fmt = puml pumlSourceToSvg;
          compute = g: render.toC4Component (graph.aspectsOnly g);
        })

        (mkView {
          view = "c4container-mmd";
          title = "C4 Container (Mermaid)";
          altText = "C4 Container Mermaid";
          fmt = mmd mmdSourceToSvg;
          compute = g: render.toC4ContainerMermaid g;
        })

        (mkView {
          view = "c4component-mmd";
          title = "C4 Component (Mermaid)";
          altText = "C4 Component Mermaid";
          fmt = mmd mmdSourceToSvg;
          compute = g: render.toC4ComponentMermaid (graph.aspectsOnly g);
        })
      ];

    # --- Per-entity views (user): core + homeManager views ---
    user = rc: (self.core rc) ++ (self.hmViews rc);

    # --- Per-entity views (home): core + homeManager views ---
    home = rc: (self.core rc) ++ (self.hmViews rc);

    # --- Fleet-level views (flake-wide, host-independent) ---
    fleet =
      {
        render,
        renderDense,
        mmdSourceToSvg,
        pumlSourceToSvg,
        ...
      }:
      [
        (mkView {
          view = "namespace";
          title = "Aspect Namespace (declarations)";
          altText = "Aspect namespace";
          fmt = mmd mmdSourceToSvg;
          compute = _: renderDense.toMermaid (graph.ofNamespace { });
        })

        (mkView {
          view = "c4context";
          title = "Fleet C4 Context";
          altText = "Fleet C4";
          fmt = puml pumlSourceToSvg;
          compute = render.toC4Context;
        })

        (mkView {
          view = "c4context-mmd";
          title = "Fleet C4 Context (Mermaid)";
          altText = "Fleet C4 Mermaid";
          fmt = mmd mmdSourceToSvg;
          compute = render.toC4ContextMermaid;
        })

        (mkView {
          view = "sankey";
          title = "Fleet Sankey";
          fmt = mmd mmdSourceToSvg;
          compute = render.toFleetSankeyMermaid;
        })

        (mkView {
          view = "treemap";
          title = "Fleet Treemap";
          fmt = mmd mmdSourceToSvg;
          compute = render.toFleetTreemapMermaid;
        })

        (mkView {
          view = "provider-matrix";
          title = "Fleet Provider Matrix";
          altText = "Provider matrix";
          fmt = mmd mmdSourceToSvg;
          compute = render.toFleetProviderMatrix;
        })
      ];
  };
in
self
