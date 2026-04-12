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
        (
          {
            view = "ctx";
            title = "Context Hierarchy";
            altText = "Context hierarchy";
          }
          // mmd mmdSourceToSvg
          // {
            compute = g: renderDense.toMermaid (graph.contextOnly g);
          }
        )

        (
          {
            view = "aspects";
            title = "Aspect Hierarchy";
            altText = "Aspect hierarchy";
          }
          // mmd mmdSourceToSvg
          // {
            compute = g: renderDense.toMermaid (graph.aspectsOnly g);
          }
        )

        (
          {
            view = "simple";
            title = "Simplified View";
            altText = "Simplified";
          }
          // mmd mmdSourceToSvg
          // {
            compute = g: renderDense.toMermaid (graph.simplified g);
          }
        )

        (
          {
            view = "seq";
            title = "Resolution Sequence";
            altText = "Sequence";
          }
          // mmd mmdSourceToSvg
          // {
            compute = g: render.toSequenceMermaid g;
          }
        )

        (
          {
            view = "seq-full";
            title = "Resolution Sequence (expanded)";
            altText = "Sequence expanded";
          }
          // mmd mmdSourceToSvg
          // {
            compute = g: render.toSequenceMermaidExpanded g;
          }
        )

        (
          {
            view = "providers";
            title = "Provider Tree";
            altText = "Providers";
          }
          // mmd mmdSourceToSvg
          // {
            compute = g: renderDense.toMermaid (graph.providersOnly g);
          }
        )

        (
          {
            view = "adapters";
            title = "Adapter Impact";
            altText = "Adapters";
          }
          // mmd mmdSourceToSvg
          // {
            compute = g: renderDense.toMermaid (graph.adaptersOnly g);
          }
        )

        (
          {
            view = "decisions";
            title = "Structural Decisions";
            altText = "Decisions";
          }
          // mmd mmdSourceToSvg
          // {
            compute = g: renderDense.toMermaid (graph.decisionsView g);
          }
        )

        (
          {
            view = "parametric";
            title = "Parametric Aspects";
            altText = "Parametric";
          }
          // mmd mmdSourceToSvg
          // {
            compute = g: renderDense.toMermaid (graph.parametricOnly g);
          }
        )

        (
          {
            view = "declared";
            title = "User-Declared Aspects";
            altText = "Declared";
          }
          // mmd mmdSourceToSvg
          // {
            compute = g: renderDense.toMermaid (graph.userDeclaredOnly g);
          }
        )

        (
          {
            view = "orphans";
            title = "Orphans and Leaves";
            altText = "Orphans and leaves";
          }
          // mmd mmdSourceToSvg
          // {
            compute = g: renderDense.toMermaid (graph.orphansAndLeaves g);
          }
        )

        (
          {
            view = "pipeline";
            title = "Resolution Pipeline (machinery)";
            altText = "Pipeline";
          }
          // mmd mmdSourceToSvg
          // {
            compute = g: renderDense.toMermaid (graph.pipelineOnly g);
          }
        )

        (
          {
            view = "state";
            title = "Context State Diagram";
            altText = "State";
          }
          // mmd mmdSourceToSvg
          // {
            compute = g: render.toStateMermaid (graph.contextOnly g);
          }
        )

        (
          {
            view = "ir";
            title = "Graph IR (JSON)";
            altText = "IR JSON";
          }
          // json
          // {
            compute = g: toJSON g;
          }
        )
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
      ++ [
        (
          {
            view = "has-aspect-nixos";
            title = "hasAspect Presence: nixos";
            altText = "hasAspect nixos";
          }
          // mmd mmdSourceToSvg
          // {
            compute = g: renderDense.toMermaid (graph.hasAspectPresent { class = "nixos"; } g);
          }
        )

        (
          {
            view = "has-aspect-hm";
            title = "hasAspect Presence: homeManager";
            altText = "hasAspect homeManager";
          }
          // mmd mmdSourceToSvg
          // {
            compute = g: renderDense.toMermaid (graph.hasAspectPresent { class = "homeManager"; } g);
          }
        )

        (
          {
            view = "class-nixos";
            title = "Class Slice: nixos";
            altText = "nixos slice";
          }
          // mmd mmdSourceToSvg
          // {
            compute = g: renderDense.toMermaid (graph.classSlice "nixos" g);
          }
        )

        (
          {
            view = "class-hm";
            title = "Class Slice: homeManager";
            altText = "homeManager slice";
          }
          // mmd mmdSourceToSvg
          // {
            compute = g: renderDense.toMermaid (graph.classSlice "homeManager" g);
          }
        )

        (
          {
            view = "cross-class";
            title = "Cross-Class Aspects";
            altText = "Cross-class";
          }
          // mmd mmdSourceToSvg
          // {
            compute = g: renderDense.toMermaid (graph.crossClassOnly g);
          }
        )

        (
          {
            view = "diff-classes";
            title = "Class Diff (nixos vs homeManager)";
            altText = "Class diff";
          }
          // mmd mmdSourceToSvg
          // {
            compute =
              g:
              renderDense.toMermaid (
                graph.diff {
                  a = graph.classSlice "nixos" g;
                  b = graph.classSlice "homeManager" g;
                }
              );
          }
        )

        (
          {
            view = "sankey";
            title = "Sankey Flow";
            altText = "Sankey";
          }
          // mmd mmdSourceToSvg
          // {
            compute = g: render.toSankeyMermaid (graph.simplified g);
          }
        )

        (
          {
            view = "treemap";
            title = "Treemap";
            altText = "Treemap";
          }
          // mmd mmdSourceToSvg
          // {
            compute = g: render.toTreemapMermaid g;
          }
        )

        (
          {
            view = "mindmap";
            title = "Provider Mindmap";
            altText = "Mindmap";
          }
          // mmd mmdSourceToSvg
          // {
            compute = g: render.toMindmapMermaid (graph.providersOnly g);
          }
        )

        (
          {
            view = "fan";
            title = "Fan-In / Fan-Out";
            altText = "Fan metrics";
          }
          // mmd mmdSourceToSvg
          // {
            compute =
              g:
              render.toFanMetricsSankey {
                rootName = g.rootName;
                metrics = graph.fanMetrics g;
              };
          }
        )

        (
          {
            view = "c4container";
            title = "C4 Container View";
            altText = "C4 Container";
          }
          // puml pumlSourceToSvg
          // {
            compute = g: render.toC4Container g;
          }
        )

        (
          {
            view = "c4component";
            title = "C4 Component View";
            altText = "C4 Component";
          }
          // puml pumlSourceToSvg
          // {
            compute = g: render.toC4Component (graph.aspectsOnly g);
          }
        )

        (
          {
            view = "c4container-mmd";
            title = "C4 Container (Mermaid)";
            altText = "C4 Container Mermaid";
          }
          // mmd mmdSourceToSvg
          // {
            compute = g: render.toC4ContainerMermaid g;
          }
        )

        (
          {
            view = "c4component-mmd";
            title = "C4 Component (Mermaid)";
            altText = "C4 Component Mermaid";
          }
          // mmd mmdSourceToSvg
          // {
            compute = g: render.toC4ComponentMermaid (graph.aspectsOnly g);
          }
        )
      ];

    # --- Per-entity views (user): core + user-specific (~16) ---
    user =
      rc@{
        render,
        renderDense,
        mmdSourceToSvg,
        pumlSourceToSvg,
        ...
      }:
      (self.core rc)
      ++ [
        (
          {
            view = "has-aspect-hm";
            title = "hasAspect Presence: homeManager";
            altText = "hasAspect homeManager";
          }
          // mmd mmdSourceToSvg
          // {
            compute = g: renderDense.toMermaid (graph.hasAspectPresent { class = "homeManager"; } g);
          }
        )

        (
          {
            view = "class-hm";
            title = "Class Slice: homeManager";
            altText = "homeManager slice";
          }
          // mmd mmdSourceToSvg
          // {
            compute = g: renderDense.toMermaid (graph.classSlice "homeManager" g);
          }
        )
      ];

    # --- Per-entity views (home): core + home-specific (~16) ---
    home =
      rc@{
        render,
        renderDense,
        mmdSourceToSvg,
        pumlSourceToSvg,
        ...
      }:
      (self.core rc)
      ++ [
        (
          {
            view = "has-aspect-hm";
            title = "hasAspect Presence: homeManager";
            altText = "hasAspect homeManager";
          }
          // mmd mmdSourceToSvg
          // {
            compute = g: renderDense.toMermaid (graph.hasAspectPresent { class = "homeManager"; } g);
          }
        )

        (
          {
            view = "class-hm";
            title = "Class Slice: homeManager";
            altText = "homeManager slice";
          }
          // mmd mmdSourceToSvg
          // {
            compute = g: renderDense.toMermaid (graph.classSlice "homeManager" g);
          }
        )
      ];

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
        (
          {
            view = "namespace";
            title = "Aspect Namespace (declarations)";
            altText = "Aspect namespace";
          }
          // mmd mmdSourceToSvg
          // {
            compute = _: renderDense.toMermaid (graph.ofNamespace { });
          }
        )

        (
          {
            view = "c4context";
            title = "Fleet C4 Context";
            altText = "Fleet C4";
          }
          // puml pumlSourceToSvg
          // {
            compute = render.toC4Context;
          }
        )

        (
          {
            view = "c4context-mmd";
            title = "Fleet C4 Context (Mermaid)";
            altText = "Fleet C4 Mermaid";
          }
          // mmd mmdSourceToSvg
          // {
            compute = render.toC4ContextMermaid;
          }
        )

        (
          {
            view = "sankey";
            title = "Fleet Sankey";
            altText = "Fleet Sankey";
          }
          // mmd mmdSourceToSvg
          // {
            compute = render.toFleetSankeyMermaid;
          }
        )

        (
          {
            view = "treemap";
            title = "Fleet Treemap";
            altText = "Fleet Treemap";
          }
          // mmd mmdSourceToSvg
          // {
            compute = render.toFleetTreemapMermaid;
          }
        )

        (
          {
            view = "provider-matrix";
            title = "Fleet Provider Matrix";
            altText = "Provider matrix";
          }
          // mmd mmdSourceToSvg
          // {
            compute = render.toFleetProviderMatrix;
          }
        )
      ];
  };
in
self
