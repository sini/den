# Sequence diagram renderer.
#
# Maps the context resolution pipeline to a sequenceDiagram:
#   - participants    = context stages (host, default, hm-host, hm-user, user)
#   - messages        = stageEdges (normal or cross-provide)
#   - notes           = aspect labels grouped per stage, truncated
#
# The pipeline is naturally sequential, so this view reveals causal flow
# (who-resolves-before-whom) rather than structural containment.
{
  lib,
  themes,
  util,
  renderUtil,
}:
let
  inherit (util) meaningful isUserAspect makeIdSanitizer;
  inherit (renderUtil) renderMermaid;

  # Stable alias for mermaid sequenceDiagram participants.
  aliasOf = makeIdSanitizer "p";

  stageLabel = util.stageLabel { };

  # Topologically order stages: roots (no incoming stageEdge) first, then rest
  # in insertion order. We only need approximate order for readability.
  orderStages =
    stages: stageEdges:
    let
      targets = lib.listToAttrs (
        map (e: {
          name = e.to;
          value = true;
        }) stageEdges
      );
      isRoot = s: !(targets ? ${s.id});
    in
    builtins.filter isRoot stages ++ builtins.filter (s: !(isRoot s)) stages;

  # Summarize a stage's aspects as a note body. Meaningful aspects only,
  # truncated so the note stays readable.
  stageNote =
    nodes: stage:
    let
      stageNodes = builtins.filter (n: n.stage == stage.name && meaningful n.label) nodes;
      labels = map (n: n.label) stageNodes;
      maxShown = 6;
      shown =
        if builtins.length labels > maxShown then
          lib.take maxShown labels ++ [ "+${toString (builtins.length labels - maxShown)} more" ]
        else
          labels;
    in
    if shown == [ ] then
      null
    else
      "    Note over ${aliasOf stage.name}: ${lib.concatStringsSep ", " shown}";

  toSequenceMermaidWith =
    {
      theme ? themes.defaultTheme,
      mermaidConfig ? { },
    }:
    graph:
    let
      inherit (graph)
        rootName
        nodes
        stages
        stageEdges
        ;
      ordered = orderStages stages stageEdges;

      participantDecl = stage: "    participant ${aliasOf stage.name} as ${stageLabel stage}";

      stageById = lib.listToAttrs (
        map (s: {
          name = s.id;
          value = s;
        }) stages
      );
      messageDecl =
        edge:
        let
          fromStage = stageById.${edge.from} or null;
          toStage = stageById.${edge.to} or null;
          fromAlias = if fromStage != null then aliasOf fromStage.name else edge.from;
          toAlias = if toStage != null then aliasOf toStage.name else edge.to;
          label = if edge.label != null then edge.label else "resolve";
          arrow = if (edge.style or "normal") == "provide" then "-->>" else "->>";
        in
        "    ${fromAlias} ${arrow} ${toAlias}: ${label}";

      # Drop self-reference stage transitions (edges where source and
      # target collapse to the same participant). They render as a
      # self-arrow in sequenceDiagram — confusing and conveys nothing
      # the stage note doesn't already say.
      nonSelfStageEdges = builtins.filter (e: e.from != e.to) stageEdges;

      notes = builtins.filter (n: n != null) (map (stageNote nodes) ordered);
    in
    if stages == [ ] then
      # No context pipeline captured — render a single-participant stub.
      renderMermaid
        {
          inherit theme mermaidConfig;
          diagramKind = "sequenceDiagram";
        }
        [
          "    participant root as ${rootName}"
          "    Note over host: no context stages captured"
        ]
    else
      renderMermaid
        {
          inherit theme mermaidConfig;
          diagramKind = "sequenceDiagram";
        }
        (
          map participantDecl ordered
          ++ [ "" ]
          ++ map messageDecl nonSelfStageEdges
          ++ (if notes != [ ] then [ "" ] ++ notes else [ ])
        );

  # Expanded variant: same stage participants and inter-stage
  # transitions as the basic sequence view but with an UNTRUNCATED
  # per-stage aspect list (rendered as a sequenceDiagram `Note over`)
  # plus explicit cross-stage provide arrows for wrapper nodes.
  #
  # Aspects are NOT emitted as per-aspect self-arrows — those render
  # as visible self-loops and bury the actual inter-stage flow. A note
  # listing every aspect conveys the same detail without the loops.
  #
  # Cross-stage projection hints: wrapper nodes matching
  # `<aspect>/<src>/(self-provide|cross-provide)(<dst>):<aspect>` become
  # src→dst arrows (same-stage self-provides filtered out). Provider
  # sub-aspects named `to-hosts` / `to-<stage>` bridge from the aspect's
  # own stage to the target stage.
  toSequenceMermaidExpandedWith =
    {
      theme ? themes.defaultTheme,
      mermaidConfig ? { },
    }:
    graph:
    let
      inherit (graph)
        rootName
        nodes
        stages
        stageEdges
        ;

      ordered = orderStages stages stageEdges;
      stageById = lib.listToAttrs (
        map (s: {
          name = s.id;
          value = s;
        }) stages
      );
      stageNames = map (s: s.name) stages;

      aspectsByStage =
        stage:
        lib.sort (a: b: a.label < b.label) (
          builtins.filter (n: n.stage == stage.name && isUserAspect graph n) nodes
        );

      # Parse wrapper labels for cross-stage provide hints.
      # Patterns we care about (matched against `fullLabel`, not `label`,
      # so aspect names stay unambiguous even if the short form was
      # chosen for display):
      #   <aspect>/<src>/self-provide(<dst>):<aspect>
      #   <aspect>/<src>/cross-provide(<dst>):<aspect>
      # Returns null for non-matching labels.
      parseProvide =
        label:
        let
          m = builtins.match "(.+)/([a-z-]+)/(self-provide|cross-provide)\\(([^)]+)\\):(.+)" label;
        in
        if m == null then
          null
        else
          {
            aspect = builtins.elemAt m 0;
            src = builtins.elemAt m 1;
            kind = builtins.elemAt m 2;
            dst = builtins.elemAt m 3;
          };

      # Wrapper nodes annotated with parsed provide info.
      provideWrappers = builtins.filter (p: p != null) (
        map (
          n:
          let
            p = parseProvide (n.fullLabel or n.label);
          in
          if p == null then null else p // { node = n; }
        ) nodes
      );

      # `alice/to-hosts` and similar provider-sub-aspects bridge stages
      # implicitly — the sub-aspect lives in one stage but its content
      # goes elsewhere via provides.* naming conventions. Detect the
      # common `to-<stage>` / `to-hosts` sub-aspects as stage bridges.
      stageBridges = lib.concatMap (
        n:
        let
          pp = n.providerPath or [ ];
          nm = if pp == [ ] then "" else n.label; # only for provider subs
          # Match trailing segment `to-hosts` or `to-<stage>`.
          tail =
            if pp == [ ] then
              null
            else
              let
                parts = lib.splitString "/" n.label;
              in
              if parts == [ ] then null else lib.last parts;
          dstStage =
            if tail == null then
              null
            else if tail == "to-hosts" then
              "host"
            else if lib.hasPrefix "to-" tail && builtins.elem (lib.removePrefix "to-" tail) stageNames then
              lib.removePrefix "to-" tail
            else
              null;
        in
        if dstStage != null && (n.stage or null) != null then
          [
            {
              src = n.stage;
              dst = dstStage;
              aspect = n.label;
              kind = "bridge";
              node = n;
            }
          ]
        else
          [ ]
      ) nodes;

      allBridges = provideWrappers ++ stageBridges;

      participantDecl = stage: "    participant ${aliasOf stage.name} as ${stageLabel stage}";

      # Per-stage block:
      #   1. Header note marking the stage
      #   2. Content note listing every user aspect in the stage (no
      #      truncation — that's the "expanded" bit)
      #   3. Non-self cross-stage bridges originating in this stage
      #   4. Non-self outgoing stage transitions from this stage
      #
      # Self-reference arrows (src == dst) are filtered at every step.
      stageBlock =
        stage:
        let
          alias = aliasOf stage.name;
          aspects = aspectsByStage stage;
          outgoing = builtins.filter (e: e.from == stage.id && e.to != stage.id) stageEdges;
          bridgesFromHere = builtins.filter (b: b.src == stage.name && b.dst != stage.name) allBridges;

          aspectsNote =
            if aspects == [ ] then
              null
            else
              "    Note over ${alias}: ${lib.concatStringsSep ", " (map (n: n.label) aspects)}";

          bridgeLine =
            b:
            let
              dstAlias = aliasOf b.dst;
              arrow = if b.kind == "cross-provide" || b.kind == "bridge" then "-->>" else "->>";
              label = if b.kind == "bridge" then "forward: ${b.aspect}" else "${b.kind}: ${b.aspect}";
            in
            "    ${alias} ${arrow} ${dstAlias}: ${label}";

          transitionLine =
            edge:
            let
              toStage = stageById.${edge.to} or null;
              toAlias = if toStage != null then aliasOf toStage.name else edge.to;
              label = if edge.label != null then edge.label else "resolve";
              arrow = if (edge.style or "normal") == "provide" then "-->>" else "->>";
            in
            "    ${alias} ${arrow} ${toAlias}: ${label}";
        in
        [
          ""
          "    Note over ${alias}: ── ${stageLabel stage}"
        ]
        ++ lib.optional (aspectsNote != null) aspectsNote
        ++ (if bridgesFromHere != [ ] then [ "" ] else [ ])
        ++ map bridgeLine bridgesFromHere
        ++ (if outgoing != [ ] then [ "" ] else [ ])
        ++ map transitionLine outgoing;
    in
    if stages == [ ] then
      renderMermaid
        {
          inherit theme mermaidConfig;
          diagramKind = "sequenceDiagram";
        }
        [
          "    participant root as ${rootName}"
          "    Note over host: no context stages captured"
        ]
    else
      renderMermaid {
        inherit theme mermaidConfig;
        diagramKind = "sequenceDiagram";
      } (map participantDecl ordered ++ lib.concatMap stageBlock ordered);

  toSequenceMermaid = toSequenceMermaidWith { };
  toSequenceMermaidExpanded = toSequenceMermaidExpandedWith { };
in
{
  inherit
    toSequenceMermaid
    toSequenceMermaidWith
    toSequenceMermaidExpanded
    toSequenceMermaidExpandedWith
    ;
}
