# PlantUML renderer: graph IR → PlantUML string.
#
# Emits `skinparam` directives derived from a theme passed via the
# render opts so the rendered SVG matches the shared palette used by
# mermaid and dot. Theme is render-time, never on the IR.
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
  inherit (renderUtil) skinparamFor visualFor;

  # Element types this renderer emits. Rectangle/Hexagon/Card are filled
  # per-node with an accent color (see `pumlStyle` below — we override the
  # fill at element declaration), so their default font color must be
  # dark (rootText) for readability on bright accent fills. Package/Note
  # inherit the clusterBg palette.
  plantumlElements = [
    "Rectangle"
    "Hexagon"
    "Card"
    "Package"
    "Note"
  ];
  plantumlAccentElements = [
    "Rectangle"
    "Hexagon"
    "Card"
  ];

  toPlantUMLWith =
    {
      theme ? themes.defaultTheme,
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
        ;
      hasStages = stages != [ ];
      rootColor = theme.rootFill;
      vf = visualFor { inherit theme nodeColorFor; };

      stageSuffix = node: if !hasStages && (node.stage or null) != null then " · ${node.stage}" else "";

      pumlShape =
        node:
        if node.shape == "hexagon" then
          "hexagon"
        else if node.shape == "trapezoid" then
          "card"
        else
          "rectangle";

      pumlLabel =
        node:
        if node.isParametric then
          "${node.label}\\n({ ${fmtArgs node.fnArgNames} })${stageSuffix node}"
        else
          "${node.label}${stageSuffix node}";

      # PlantUML: `#fill` sets background; `;line.dashed` appends a dashed
      # border. Chaining style directives with `;` is the supported form.
      pumlStyle =
        node:
        let
          v = vf node;
        in
        if v.isExcluded || v.isReplaced then " ${v.fill};line.dashed" else " ${v.fill}";

      nodeDecl = node: "${pumlShape node} \"${pumlLabel node}\" as ${node.id}${pumlStyle node}";

      edgeDecl =
        edge:
        let
          arrow =
            if edge.style == "excluded" then
              "..x"
            else if edge.style == "replaced" then
              "..>"
            else
              "-->";
          label = if edge.label != null then " : ${edge.label}" else "";
        in
        "${edge.from} ${arrow} ${edge.to}${label}";

      stageSubgraph =
        stage:
        let
          stageNodes = builtins.filter (n: n.stage == stage.name && n.id != rootId) nodes;
          ctxLabel = if stage.ctxKeys != [ ] then " { ${lib.concatStringsSep ", " stage.ctxKeys} }" else "";
        in
        lib.optional (stageNodes != [ ]) (
          "package \"${stage.name}${ctxLabel}\" {\n"
          + lib.concatMapStringsSep "\n" (n: "  ${nodeDecl n}") stageNodes
          + "\n}"
        );
    in
    lib.concatStringsSep "\n" (
      [
        "@startuml"
        (skinparamFor {
          inherit theme;
          elements = plantumlElements;
          onAccentFill = plantumlAccentElements;
        })
        "rectangle \"${rootName}\" as ${rootId} ${rootColor}"
      ]
      ++ lib.concatMap stageSubgraph stages
      ++ map nodeDecl (builtins.filter (n: n.stage == null && n.id != rootId) nodes)
      ++ [ "" ]
      ++ map edgeDecl edges
      ++ map edgeDecl stageEdges
      ++ [ "@enduml" ]
    );
  toPlantUML = toPlantUMLWith { };
in
{
  inherit toPlantUML toPlantUMLWith;
}
