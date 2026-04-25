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

  nodeLabel =
    n:
    let
      base = n.label or n.name or "<anon>";
      args = n.fnArgNames or [ ];
    in
    if args != [ ] then "${base}(${util.fmtArgs args})" else base;

  noteWrapAt = 4;

  # Word-wrap a label list into <br/>-joined chunks of noteWrapAt.
  wrapLabels =
    labels:
    let
      len = builtins.length labels;
      numChunks = if len == 0 then 0 else (len + noteWrapAt - 1) / noteWrapAt;
    in
    lib.concatStringsSep "<br/>" (
      builtins.filter (c: c != "") (
        lib.genList (
          i: lib.concatStringsSep ", " (lib.take noteWrapAt (lib.drop (i * noteWrapAt) labels))
        ) numChunks
      )
    );

  mkStageById =
    stages:
    lib.listToAttrs (
      map (s: {
        name = s.id;
        value = s;
      }) stages
    );

  policyNodesOf = nodes: builtins.filter (n: n.isPolicyDispatch or false) nodes;

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

      stageById = mkStageById stages;
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

      # Policy dispatch messages with context annotation.
      policyNodes = policyNodesOf nodes;
      policyMessages = lib.concatMap (
        pn:
        let
          fromStage = pn.from or null;
          toStage = pn.to or null;
          fromAlias = if fromStage != null then aliasOf fromStage else null;
          toAlias = if toStage != null then aliasOf toStage else null;
          policyName = pn.policyName or pn.label;
        in
        lib.optional (
          fromAlias != null && toAlias != null && fromAlias != toAlias
        ) "    ${fromAlias} -->> ${toAlias}: ${policyName}"
      ) policyNodes;

      # Per-stage aspect blocks: show parametric aspects with their args
      # and non-parametric aspects grouped separately.
      stageBlock =
        stage:
        let
          alias = aliasOf stage.name;
          stageNodes = builtins.filter (
            n: n.stage == stage.name && meaningful n.label && !(n.isPolicyDispatch or false)
          ) nodes;
          parametric = builtins.filter (n: (n.fnArgNames or [ ]) != [ ]) stageNodes;
          static = builtins.filter (n: (n.fnArgNames or [ ]) == [ ]) stageNodes;
          parametricLines = map (n: "    ${alias} ->> ${alias}: ${nodeLabel n}") parametric;
          staticLabels = map (n: n.label) static;
          staticNote = wrapLabels staticLabels;
        in
        (
          if parametricLines != [ ] then
            [ "    activate ${alias}" ] ++ parametricLines ++ [ "    deactivate ${alias}" ]
          else
            [ ]
        )
        ++ lib.optional (staticNote != "") "    Note over ${alias}: ${staticNote}";
    in
    if stages == [ ] then
      renderMermaid
        {
          inherit theme mermaidConfig;
          diagramKind = "sequenceDiagram";
        }
        [
          "    participant root as ${rootName}"
          "    Note over root: no context stages captured"
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
          ++ (if policyMessages != [ ] then [ "" ] ++ policyMessages else [ ])
          ++ lib.concatMap (s: [ "" ] ++ stageBlock s) ordered
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
      stageById = mkStageById stages;
      aspectsByStage =
        stage:
        lib.sort (a: b: a.label < b.label) (
          builtins.filter (n: n.stage == stage.name && isUserAspect graph n) nodes
        );

      allBridges = util.detectBridges graph;

      participantDecl = stage: "    participant ${aliasOf stage.name} as ${stageLabel stage}";

      # Per-stage block:
      #   1. Header note marking the stage
      #   2. Content note listing every user aspect in the stage (no
      #      truncation — that's the "expanded" bit)
      #   3. Non-self cross-stage bridges originating in this stage
      #   4. Non-self outgoing stage transitions from this stage
      #
      # Self-reference arrows (src == dst) are filtered at every step.
      # Policy nodes grouped by source stage for dispatch arrows.
      policyNodesByStage =
        stage: builtins.filter (n: (n.isPolicyDispatch or false) && (n.from or null) == stage.name) nodes;

      stageBlock =
        stage:
        let
          alias = aliasOf stage.name;
          aspects = aspectsByStage stage;
          outgoing = builtins.filter (e: e.from == stage.id && e.to != stage.id) stageEdges;
          bridgesFromHere = builtins.filter (b: b.src == stage.name && b.dst != stage.name) allBridges;
          stagePolicies = policyNodesByStage stage;

          # Split aspects into parametric (with ctx args) and static.
          parametric = builtins.filter (n: (n.fnArgNames or [ ]) != [ ]) aspects;
          static = builtins.filter (n: (n.fnArgNames or [ ]) == [ ]) aspects;

          # Parametric aspects as self-arrows with arg annotation.
          parametricLines =
            if parametric == [ ] then
              [ ]
            else
              [ "    activate ${alias}" ]
              ++ map (n: "    ${alias} ->> ${alias}: ${nodeLabel n}") parametric
              ++ [ "    deactivate ${alias}" ];

          # Static aspects as word-wrapped note.
          staticLabels = map (n: n.label) static;
          staticChunks = lib.genList (
            i: lib.concatStringsSep ", " (lib.take noteWrapAt (lib.drop (i * noteWrapAt) staticLabels))
          ) (if staticLabels == [ ] then 0 else (builtins.length staticLabels + noteWrapAt - 1) / noteWrapAt);
          staticNote = lib.concatStringsSep "<br/>" (builtins.filter (c: c != "") staticChunks);

          # Policy dispatch arrows from this stage.
          policyLines = lib.concatMap (
            pn:
            let
              toStage = pn.to or null;
              toAlias = if toStage != null then aliasOf toStage else null;
              policyName = pn.policyName or pn.label;
            in
            lib.optional (toAlias != null && toAlias != alias) "    ${alias} -->> ${toAlias}: ${policyName}"
          ) stagePolicies;

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
              toStage' = stageById.${edge.to} or null;
              toAlias = if toStage' != null then aliasOf toStage'.name else edge.to;
              label = if edge.label != null then edge.label else "resolve";
              arrow = if (edge.style or "normal") == "provide" then "-->>" else "->>";
            in
            "    ${alias} ${arrow} ${toAlias}: ${label}";
        in
        [
          ""
          "    Note over ${alias}: ── ${stageLabel stage}"
        ]
        ++ parametricLines
        ++ lib.optional (staticNote != "") "    Note over ${alias}: ${staticNote}"
        ++ (if bridgesFromHere != [ ] then [ "" ] else [ ])
        ++ map bridgeLine bridgesFromHere
        ++ (if policyLines != [ ] then [ "" ] else [ ])
        ++ policyLines
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
          "    Note over root: no context stages captured"
        ]
    else
      renderMermaid {
        inherit theme mermaidConfig;
        diagramKind = "sequenceDiagram";
      } (map participantDecl ordered ++ lib.concatMap stageBlock ordered);

  toSequenceMermaid = toSequenceMermaidWith { };
  toSequenceMermaidExpanded = toSequenceMermaidExpandedWith { };

  # Stage topology: focused flowchart showing only pipeline stages and
  # their transition edges. Answers "what is the resolution order?"
  # without any aspect-level detail.
  toStageEdgesMermaidWith =
    {
      theme ? themes.defaultTheme,
      mermaidConfig ? { },
    }:
    graph:
    let
      inherit (graph) stages stageEdges rootName;
      ordered = orderStages stages stageEdges;
      stageById = mkStageById stages;
      nodeDecl = stage: "    ${aliasOf stage.name}([${stageLabel stage}])";
      edgeDecl =
        edge:
        let
          fromStage = stageById.${edge.from} or null;
          toStage = stageById.${edge.to} or null;
        in
        if fromStage == null || toStage == null then
          null
        else
          let
            arrow = if (edge.style or "normal") == "provide" then "-.->" else "-->";
            lbl = if edge.label != null then "|${edge.label}|" else "";
          in
          "    ${aliasOf fromStage.name} ${arrow}${lbl} ${aliasOf toStage.name}";
      edgeLines = builtins.filter (l: l != null) (map edgeDecl stageEdges);
    in
    if stages == [ ] then
      renderMermaid {
        inherit theme mermaidConfig;
        diagramKind = "graph LR";
      } [ "    root([${rootName}])" ]
    else
      renderMermaid {
        inherit theme mermaidConfig;
        diagramKind = "graph LR";
      } (map nodeDecl ordered ++ (if edgeLines != [ ] then [ "" ] ++ edgeLines else [ ]));

  toStageEdgesMermaid = toStageEdgesMermaidWith { };

  # Policy-centric sequence: policies ARE the participants.
  # Shows each policy as an actor, what context it receives,
  # what aspects it triggers, and how policies chain.
  toPolicySequenceMermaidWith =
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

      policyNodes = lib.sort (
        a: b:
        (a.from or "") < (b.from or "") || ((a.from or "") == (b.from or "") && (a.to or "") < (b.to or ""))
      ) (builtins.filter (n: n.isPolicyDispatch or false) nodes);

      # Aspects grouped by target stage.
      aspectsByStage =
        stageName:
        builtins.filter (
          n: n.stage == stageName && meaningful n.label && !(n.isPolicyDispatch or false)
        ) nodes;

      # Root entity participant.
      rootParticipant = "    participant root as ${rootName}";

      # Each policy becomes a participant.
      policyParticipants = map (
        pn: "    participant ${aliasOf (pn.policyName or pn.label)} as ${pn.policyName or pn.label}"
      ) policyNodes;

      childrenOf = (util.adjacency (graph.edges or [ ])).outOf;

      nodeById = lib.listToAttrs (
        map (n: {
          name = n.id;
          value = n;
        }) nodes
      );

      # For each policy: root dispatches to it, it activates and shows
      # the aspects it triggers grouped by entity.
      policyBlock =
        pn:
        let
          pAlias = aliasOf (pn.policyName or pn.label);
          toStage = pn.to or null;

          targetAspects = if toStage != null then aspectsByStage toStage else [ ];

          # Top-level entities in this stage (parametric aspects with the
          # stage's context args — alice, bob, deploy, etc.)
          topEntities = builtins.filter (
            n:
            (n.fnArgNames or [ ]) != [ ]
            && !(lib.hasPrefix "provides/" n.label)
            && !(lib.hasPrefix "${toStage}/" n.label)
          ) targetAspects;

          # Group aspects by parent entity using edge relationships.
          entityBlock =
            entity:
            let
              childIds = childrenOf.${entity.id} or [ ];
              children = builtins.filter (n: builtins.elem n.id childIds && n.id != entity.id) targetAspects;
              childLabels = map (n: nodeLabel n) children;
            in
            [ "    Note over ${pAlias}: ${nodeLabel entity}" ]
            ++ map (l: "    ${pAlias} ->> ${pAlias}: ${l}") childLabels;

          # Aspects not parented to any top entity (stage-level).
          topEntityIds = map (n: n.id) topEntities;
          allEntityChildIds = lib.concatMap (e: childrenOf.${e.id} or [ ]) topEntities;
          orphans = builtins.filter (
            n: !(builtins.elem n.id topEntityIds) && !(builtins.elem n.id allEntityChildIds)
          ) targetAspects;
          orphanLabels = map (n: nodeLabel n) orphans;
          orphanNote = wrapLabels orphanLabels;

          # Downstream policy chains.
          downstream = builtins.filter (p2: (p2.from or null) == toStage && p2 != pn) policyNodes;
          chainLines = map (
            p2: "    ${pAlias} -->> ${aliasOf (p2.policyName or p2.label)}: chains"
          ) downstream;
        in
        [
          ""
          "    root ->> ${pAlias}: dispatch"
          "    activate ${pAlias}"
        ]
        ++ lib.concatMap entityBlock topEntities
        ++ lib.optional (orphanNote != "") "    Note over ${pAlias}: ${orphanNote}"
        ++ chainLines
        ++ [ "    deactivate ${pAlias}" ];

      # Deduplicate: only show aspects for the first policy targeting
      # each stage.
      seenStages =
        builtins.foldl'
          (
            acc: pn:
            let
              to = pn.to or "";
              isFirst = !(acc.seen ? ${to});
              pAlias = aliasOf (pn.policyName or pn.label);
            in
            {
              seen = acc.seen // {
                ${to} = true;
              };
              blocks =
                acc.blocks
                ++ (
                  if isFirst then
                    policyBlock pn
                  else
                    [
                      ""
                      "    root ->> ${pAlias}: dispatch"
                    ]
                );
            }
          )
          {
            seen = { };
            blocks = [ ];
          }
          policyNodes;
    in
    if policyNodes == [ ] then
      renderMermaid
        {
          inherit theme mermaidConfig;
          diagramKind = "sequenceDiagram";
        }
        [
          "    participant root as ${rootName}"
          "    Note over root: no policies captured"
        ]
    else
      renderMermaid {
        inherit theme mermaidConfig;
        diagramKind = "sequenceDiagram";
      } ([ rootParticipant ] ++ policyParticipants ++ seenStages.blocks);

  toPolicySequenceMermaid = toPolicySequenceMermaidWith { };

in
{
  inherit
    toSequenceMermaid
    toSequenceMermaidWith
    toSequenceMermaidExpanded
    toSequenceMermaidExpandedWith
    toStageEdgesMermaid
    toStageEdgesMermaidWith
    toPolicySequenceMermaid
    toPolicySequenceMermaidWith
    ;
}
