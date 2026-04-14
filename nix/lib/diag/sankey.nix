# Sankey flow diagrams (mermaid sankey-beta).
#
# The inclusion hierarchy mapped onto a sankey diagram: each edge carries
# weight = the number of leaves reachable from its target node. Edges near
# the root accumulate a lot of flow (many descendants); edges near leaves
# carry weight 1. The resulting diagram narrows naturally with depth and
# reveals where a host's configuration mass lives.
#
# Per-host: flows from host → top-level aspects → descendants → leaves.
# Fleet:    flows from users → hosts, weighted by class count, so a
#           user that configures many hosts produces a wide ribbon.
{
  lib,
  themes,
  util,
  renderUtil,
}:
let
  inherit (util) dedupBy adjacency;
  inherit (renderUtil) renderMermaid;

  # Sankey uses CSV rows per edge. Labels are quoted (RFC 4180 style) so
  # commas and whitespace in aspect names don't break parsing.
  csvQuote = s: "\"${lib.replaceStrings [ "\"" ] [ "\"\"" ] s}\"";

  # --- Per-host sankey: depth-oriented inclusion flow ---
  toSankeyMermaidWith =
    {
      theme ? themes.defaultTheme,
      mermaidConfig ? { },
    }:
    graph:
    let
      inherit (graph)
        rootId
        rootName
        nodes
        edges
        ;

      # Dedup edges, drop self-loops, and break cycles.
      # Sankey diagrams don't support any circular links.
      noSelfLoops = builtins.filter (e: e.from != e.to) edges;
      dedupedEdges = dedupBy (e: "${e.from}->${e.to}") noSelfLoops;
      fwdAdj = (adjacency dedupedEdges).outOf;
      isReachable =
        start: target: visited:
        if start == target then
          true
        else if visited ? ${start} then
          false
        else
          builtins.any (next: isReachable next target (visited // { ${start} = true; })) (
            fwdAdj.${start} or [ ]
          );
      uniqueEdges = builtins.filter (e: !(isReachable e.to e.from { })) dedupedEdges;

      childMap = (adjacency uniqueEdges).outOf;

      # Number of leaves reachable from `id`. Visited set guards against
      # accidental cycles (e.g. cross-provide or provider-provenance edges).
      # A leaf counts as 1; an interior node sums its children.
      leafCount =
        id: visited:
        if visited ? ${id} then
          1
        else
          let
            next = visited // {
              ${id} = true;
            };
            kids = childMap.${id} or [ ];
          in
          if kids == [ ] then 1 else lib.foldl' (acc: k: acc + leafCount k next) 0 kids;

      nodeById = lib.listToAttrs (
        map (n: {
          name = n.id;
          value = n;
        }) nodes
      );
      labelOf =
        id:
        if id == rootId then
          rootName
        else if nodeById ? ${id} then
          nodeById.${id}.label
        else
          id;

      edgeLine =
        e:
        let
          w = leafCount e.to { };
        in
        "${csvQuote (labelOf e.from)},${csvQuote (labelOf e.to)},${toString w}";
    in
    if uniqueEdges == [ ] then
      renderMermaid
        {
          inherit theme mermaidConfig;
          diagramKind = "sankey-beta";
        }
        [
          ""
          "${csvQuote rootName},${csvQuote "(no aspects)"},1"
        ]
    else
      renderMermaid {
        inherit theme mermaidConfig;
        diagramKind = "sankey-beta";
      } ([ "" ] ++ map edgeLine uniqueEdges);

  # --- Fleet sankey: user → host provisioning flow ---
  #
  # Each user-to-host relation carries weight = number of classes the user
  # brings (`label` is a `+`-joined class list). This gives wider ribbons
  # for users with multiple classes on the same host.
  toFleetSankeyMermaidWith =
    {
      theme ? themes.defaultTheme,
      mermaidConfig ? { },
    }:
    fleet:
    let
      inherit (fleet) relations;
      relLine =
        rel:
        let
          weight = if rel.label == "uses" then 1 else builtins.length (lib.splitString "+" rel.label);
        in
        "${csvQuote rel.from},${csvQuote rel.to},${toString weight}";
    in
    if relations == [ ] then
      renderMermaid
        {
          inherit theme mermaidConfig;
          diagramKind = "sankey-beta";
        }
        [
          ""
          "${csvQuote fleet.flakeName},${csvQuote "(empty fleet)"},1"
        ]
    else
      renderMermaid {
        inherit theme mermaidConfig;
        diagramKind = "sankey-beta";
      } ([ "" ] ++ map relLine relations);

  # --- Fan-metrics sankey: flow weight = aspect reuse (fan-in) ---
  #
  # Takes a list of `{ id, label, fanIn, fanOut, total, ... }` records
  # (e.g. from `diag.graph.fanMetrics graph`) and emits a sankey that
  # flows host → aspect with weight = fanIn (reuse count), truncated
  # to the top N by total so huge graphs stay readable. Reveals which
  # aspects are the "library" (high fanIn) and which are orchestrators
  # (high fanOut).
  toFanMetricsSankeyWith =
    {
      theme ? themes.defaultTheme,
      mermaidConfig ? { },
      topN ? 30,
    }:
    { rootName, metrics }:
    let
      nonZero = builtins.filter (m: m.fanIn > 0 || m.fanOut > 0) metrics;
      top = lib.take topN nonZero;
      fanInLines = map (m: "${csvQuote m.label},${csvQuote "reused"},${toString m.fanIn}") (
        builtins.filter (m: m.fanIn > 0) top
      );
      fanOutLines = map (m: "${csvQuote "orchestrates"},${csvQuote m.label},${toString m.fanOut}") (
        builtins.filter (m: m.fanOut > 0) top
      );
    in
    if top == [ ] then
      renderMermaid
        {
          inherit theme mermaidConfig;
          diagramKind = "sankey-beta";
        }
        [
          ""
          "${csvQuote rootName},${csvQuote "(no measurable fan)"},1"
        ]
    else
      renderMermaid {
        inherit theme mermaidConfig;
        diagramKind = "sankey-beta";
      } ([ "" ] ++ fanInLines ++ fanOutLines);

  toSankeyMermaid = toSankeyMermaidWith { };
  toFleetSankeyMermaid = toFleetSankeyMermaidWith { };
  toFanMetricsSankey = toFanMetricsSankeyWith { };
in
{
  inherit
    toSankeyMermaid
    toSankeyMermaidWith
    toFleetSankeyMermaid
    toFleetSankeyMermaidWith
    toFanMetricsSankey
    toFanMetricsSankeyWith
    ;
}
