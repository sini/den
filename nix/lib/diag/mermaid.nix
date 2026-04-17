# Mermaid renderer: graph IR → Mermaid diagram string.
#
# Emits a YAML frontmatter preamble derived from a theme record so that
# mermaid's themeVariables propagate to every downstream diagram type.
# All colors come from the theme; nothing is hardcoded. The graph IR
# carries no theme or color data — both arrive via the render opts.
#
# `toMermaidWith` accepts an opts record:
#
#   { theme ? themes.defaultTheme
#     # Base16-derived theme record (see diag.themeFromBase16).
#
#   , mermaidConfig ? {}
#     # Extra config merged over the theme-derived base. Good for
#     # layout tweaks, flowchart options, themeVariables overrides.
#   }
#
# Example — switch a dense flowchart to ELK layout:
#
#   diag.toMermaidWith {
#     inherit theme;
#     mermaidConfig = {
#       layout = "elk";
#       elk = {
#         mergeEdges = true;
#         nodePlacementStrategy = "LINEAR_SEGMENTS";
#       };
#     };
#   } graph;
#
# Example — force-directed layout via cose-bilkent (availability
# depends on the mermaid layout plugins in use):
#
#   diag.toMermaidWith {
#     inherit theme;
#     mermaidConfig = {
#       layout = "cose-bilkent";
#       # cose-bilkent specific tuning goes under its own key if
#       # the plugin reads one. Most deployments only need `layout`.
#     };
#   } graph;
{
  lib,
  themes,
  colors,
  util,
  renderUtil,
}:
let
  inherit (colors) nodeColorFor;
  inherit (util) fmtArgs;
  inherit (renderUtil) renderMermaid visualFor;

  toMermaidWith =
    {
      theme ? themes.defaultTheme,
      mermaidConfig ? { },
    }:
    graph:
    let
      inherit (graph)
        rootName
        rootId
        nodes
        edges
        stages
        stageEdges
        direction
        ;
      hasStages = stages != [ ];
      nodeById = builtins.listToAttrs (
        map (n: {
          name = n.id;
          value = n;
        }) nodes
      );
      rootColor = theme.rootFill;
      vf = visualFor { inherit theme nodeColorFor; };

      # When the graph has no stage subgraphs (flat views like providers,
      # adapters, parametric, simple), append the node's stage to the
      # label as a context decoration: `label · stage`. In stage-grouped
      # views the stage is already visible via the subgraph cluster, so
      # no decoration is added there.
      #
      # `stageSuffix` lives AFTER parametric fnArgs so hexagon labels
      # read `name({ args }) · stage` (not `name · stage({ args })`).
      stageSuffix = node: if !hasStages && (node.stage or null) != null then " · ${node.stage}" else "";

      mermaidShape =
        node:
        if node.shape == "hexagon" then
          "{{\"${node.label}({ ${fmtArgs node.fnArgNames} })${stageSuffix node}\"}}"
        else if node.shape == "trapezoid" then
          "[/\"${node.label}${stageSuffix node}\"\\]"
        else
          "[\"${node.label}${stageSuffix node}\"]";

      # Every node gets its own per-node class. Excluded/replaced nodes
      # don't fall through to a flat `excluded` / `replaced` class —
      # that would collapse every excluded node onto one color. Instead
      # they share the per-node accent fill and signal state via the
      # border color + dash pattern (see nodeColorDefs).
      mermaidStyle = node: ":::${node.id}_c";

      mermaidArrow =
        edge:
        if edge.style == "replaced" then
          "-.->|replaced|"
        else if edge.style == "excluded" then
          "-.-x"
        else if edge.style == "provide" then
          "-.->|${edge.label}|"
        else
          "-->";

      nodeDecl = node: "  ${node.id}${mermaidShape node}${mermaidStyle node}";
      edgeDecl = edge: "  ${edge.from} ${mermaidArrow edge} ${edge.to}";

      stageSubgraph =
        stage:
        let
          stageNodes = builtins.filter (n: n.stage == stage.name && n.id != rootId) nodes;
          stageEdgesList = builtins.filter (
            e:
            let
              fromNode = nodeById.${e.from} or null;
            in
            fromNode != null && fromNode.stage == stage.name
          ) edges;
          ctxLabel = if stage.ctxKeys != [ ] then " { ${lib.concatStringsSep ", " stage.ctxKeys} }" else "";
        in
        lib.optional (stageNodes != [ ]) (
          "  subgraph ${stage.id}[\"${stage.name}${ctxLabel}\"]\n"
          + lib.concatMapStringsSep "\n" nodeDecl stageNodes
          + "\n"
          + lib.concatMapStringsSep "\n" edgeDecl stageEdgesList
          + "\n  end"
        );

      # `topLevelNodes` are the nodes declared outside any stage subgraph.
      # When the graph is flat (no stages), that's every non-host node.
      # When the graph has stage subgraphs, it's only the stage-null
      # nodes (the others get declared inside their subgraph block).
      topLevelNodes =
        if hasStages then
          builtins.filter (n: n.stage == null && n.id != rootId) nodes
        else
          builtins.filter (n: n.id != rootId) nodes;
      unmappedEdges = builtins.filter (
        e:
        let
          fromNode = nodeById.${e.from} or null;
        in
        fromNode != null && fromNode.stage == null
      ) edges;

      # Stages that would *not* get a subgraph declaration because they
      # contain no user-visible nodes, yet are still referenced by stageEdges.
      # Emit a stub node declaration so mermaid shows the friendly label
      # instead of rendering the raw sanitized ID.
      nonEmptyStageIds = map (s: s.id) (
        builtins.filter (s: builtins.any (n: n.stage == s.name) nodes) stages
      );
      referencedStageIds = lib.unique (
        lib.concatMap (e: [
          e.from
          e.to
        ]) stageEdges
      );
      stubStages = builtins.filter (
        s: builtins.elem s.id referencedStageIds && !(builtins.elem s.id nonEmptyStageIds)
      ) stages;
      stubStageDecl =
        stage:
        let
          ctxLabel = if stage.ctxKeys != [ ] then " { ${lib.concatStringsSep ", " stage.ctxKeys} }" else "";
        in
        "  ${stage.id}[\"${stage.name}${ctxLabel}\"]";

      # Per-node class declarations. Fill/stroke/text come from visualFor
      # so changing the theme reshuffles colors without IR rebuilding.
      # The borderExtra string is still mermaid-specific CSS (dash patterns
      # + stroke widths) and stays local to this renderer.
      #
      # Excluded / replaced nodes get the per-node accent fill too; the
      # 5-5 dash pattern + stroke color (excludedStroke / replacedStroke
      # from visualFor) signals state while keeping each node individually
      # colored.
      #
      # Diff views set `node.origin` — a (removed) / b (added) / both.
      # In a diff view the origin tag takes precedence over the default
      # style, because seeing "this was added by the right-hand graph"
      # is the whole point.
      nodeColorDefs = map (
        node:
        let
          v = vf node;
          origin = node.origin or null;
          # diff-specific stroke overrides accent when origin is set
          diffStroke =
            if origin == "a" then
              theme.excludedStroke
            else if origin == "b" then
              theme.rootStroke
            else
              v.stroke;
          borderExtra =
            if origin == "a" then
              ",stroke-dasharray: 5 5,stroke-width:3px"
            else if origin == "b" then
              ",stroke-width:4px"
            else if v.isExcluded || v.isReplaced then
              ",stroke-dasharray: 5 5,stroke-width:2px"
            else if v.isAdapter then
              ",stroke-width:3px"
            else if !node.hasClass then
              ",stroke-dasharray: 3 3,stroke-width:1px"
            else
              ",stroke-width:2px";
        in
        "  classDef ${node.id}_c fill:${v.fill},stroke:${diffStroke},color:${v.text}${borderExtra}"
      ) nodes;
    in
    renderMermaid
      {
        inherit theme mermaidConfig;
        diagramKind = "graph ${direction}";
      }
      (
        [ "  ${rootId}([${rootName}]):::root" ]
        ++ map nodeDecl topLevelNodes
        ++ [ "" ]
        ++ (
          if hasStages then
            lib.concatMap stageSubgraph stages
            ++ map stubStageDecl stubStages
            ++ [ "" ]
            ++ map edgeDecl stageEdges
            ++ map edgeDecl unmappedEdges
          else
            map edgeDecl edges
        )
        ++ [
          ""
          "  classDef root fill:${theme.rootFill},stroke:${theme.rootStroke},color:${theme.rootText},font-weight:bold"
        ]
        ++ nodeColorDefs
        ++ lib.optionals hasStages (
          map (
            s: "style ${s.id} fill:${theme.clusterBg},stroke:${theme.clusterBorder},stroke-width:2px"
          ) stages
        )
      );
  # Back-compat: zero-config form stays the same shape the rest of the
  # library uses (`diag.toMermaid graph`), while callers needing to
  # tweak frontmatter can use `diag.toMermaidWith { … } graph`.
  toMermaid = toMermaidWith { };
in
{
  inherit toMermaid toMermaidWith;
}
