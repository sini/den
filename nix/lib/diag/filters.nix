# Graph filters and reshape operations.
#
# Every function in this file takes a graph IR (as produced by
# `graph.nix`'s `buildGraph`) and returns a new graph IR — a strictly
# structural transformation, no rendering. The result is consumed by
# the renderer modules (mermaid / dot / plantuml / etc).
#
# Filters fall into a few rough categories:
#
#   - predicate filters         (filterMeaningful, userDeclaredOnly,
#                                pipelineOnly, crossClassOnly)
#   - reshape / synthesize      (contextOnly, providersOnly)
#   - fold / collapse           (foldWrappers, foldProviders,
#                                flattenStages, simplified)
#   - closure-based             (classSlice, neighborhoodOf,
#                                adaptersOnly, parametricOnly)
#   - lint / metrics            (orphansAndLeaves, fanMetrics)
#   - merge                     (diff)
#
# Most of the mechanics (id-set building, edge pruning, adjacency
# walks) live in `util.nix`'s subgraph primitives —
# `filterByNodes`, `neighborhoodByNodes`, `ancestorClosureBy`,
# `adjacency`, etc. — so filters here are thin predicate-plus-glue.
{
  lib,
  util,
  graphLib,
}:
let
  inherit (util)
    dedupBy
    meaningful
    isWrapper
    isTombstone
    adjacency
    filterByNodes
    neighborhoodByNodes
    ancestorClosureBy
    ;
  inherit (graphLib) emptyNode;

  # Drop provider-provenance edges (`subAspect → provider`) from an
  # edge list. Used by filters that reason about "children" in the
  # inclusion sense — provider edges run in the opposite direction
  # and will contaminate `adjacency.outOf` lookups.
  inclusionEdgesOnly = edges: builtins.filter (e: (e.style or "normal") != "provide") edges;

  # Remove anonymous nodes, function bodies, and module merge artifacts.
  filterMeaningful = filterByNodes (n: meaningful n.label);

  # Fold wrapper nodes into their children. Wrapper nodes (stage/kind patterns
  # and context nodes) are removed, and their parent edges are rewired to
  # point directly at the wrapper's children.
  foldWrappers =
    graph:
    let
      isContextNode =
        label:
        builtins.elem label [
          "host"
          "default"
          "hm-host"
          "hm-user"
          "user"
        ];
      isFoldable = n: !meaningful n.label || isWrapper n.label || isContextNode n.label;

      foldIds = lib.listToAttrs (
        map (n: {
          name = n.id;
          value = true;
        }) (builtins.filter isFoldable graph.nodes)
      );

      # Adjacency built once; previous implementation linear-scanned
      # graph.edges for every expansion step (O(V·E·depth)).
      adj = adjacency graph.edges;
      childrenOf = id: adj.outOf.${id} or [ ];
      parentsOf = id: adj.inTo.${id} or [ ];

      # Expand edges: replace foldable endpoints with their non-foldable connections.
      # Track visited set to prevent infinite recursion from cycles among foldable nodes.
      expandFrom = expandFromWith { };
      expandFromWith =
        visited: from:
        if !(foldIds ? ${from}) then
          [ from ]
        else if visited ? ${from} then
          [ ]
        else
          lib.concatMap (expandFromWith (visited // { ${from} = true; })) (parentsOf from);
      expandTo = expandToWith { };
      expandToWith =
        visited: to:
        if !(foldIds ? ${to}) then
          [ to ]
        else if visited ? ${to} then
          [ ]
        else
          lib.concatMap (expandToWith (visited // { ${to} = true; })) (childrenOf to);

      expandedEdges = lib.concatMap (
        edge:
        let
          froms = expandFrom edge.from;
          tos = expandTo edge.to;
        in
        lib.concatMap (
          f:
          map (
            t:
            edge
            // {
              from = f;
              to = t;
            }
          ) tos
        ) froms
      ) graph.edges;

      keptNodes = builtins.filter (n: !(foldIds ? ${n.id})) graph.nodes;
      keptIds = lib.listToAttrs (
        map (n: {
          name = n.id;
          value = true;
        }) keptNodes
      );
      keptEdges = dedupBy (e: "${e.from}->${e.to}") (
        builtins.filter (e: keptIds ? ${e.from} && keptIds ? ${e.to} && e.from != e.to) expandedEdges
      );
    in
    graph
    // {
      nodes = keptNodes;
      edges = keptEdges;
    };

  # Remove anonymous nodes AND fold context pipeline wrappers into their children.
  filterUserAspects = graph: foldWrappers (filterMeaningful graph);

  # Context hierarchy only: reshape the graph so the context pipeline stages
  # become the nodes. Aspect content is discarded. The host node is retained
  # and connected to entry stages (those with no incoming stage transition)
  # so the rendered graph reads "host → first stage → …".
  contextOnly =
    graph:
    let
      stageLabel_ =
        stage:
        stage.name
        + (if stage.ctxKeys != [ ] then " { ${lib.concatStringsSep ", " stage.ctxKeys} }" else "");
      stageNodes = map (
        stage:
        emptyNode
        // {
          id = stage.id;
          label = stageLabel_ stage;
          fullLabel = stageLabel_ stage;
          # Synthetic "context" stage so render-time color hashing puts
          # the pipeline stages into their own hue band.
          stage = "context";
          hasClass = true;
        }
      ) graph.stages;

      stageTargets = map (e: e.to) graph.stageEdges;
      entryStages = builtins.filter (s: !(builtins.elem s.id stageTargets)) stageNodes;
      hostEdges = map (s: {
        from = graph.rootId;
        to = s.id;
        style = "normal";
        label = null;
      }) entryStages;
    in
    graph
    // {
      nodes = stageNodes;
      edges = hostEdges ++ graph.stageEdges;
      stages = [ ];
      stageEdges = [ ];
    };

  # Aspect hierarchy only: user aspects with context wrappers folded out
  # and provider-provenance edges dropped. Stage subgraphs are retained as
  # visual grouping (nixos / homeManager / etc).
  aspectsOnly =
    graph:
    let
      filtered = filterUserAspects graph;
    in
    filtered
    // {
      edges = builtins.filter (e: (e.style or "normal") != "provide") filtered.edges;
    };

  # Drop stage subgraph grouping so nodes render as a single flat DAG.
  flattenStages =
    graph:
    graph
    // {
      nodes = map (n: n // { stage = null; }) graph.nodes;
      stages = [ ];
      stageEdges = [ ];
    };

  # Fold provider sub-aspects into their parent providers. For a node with
  # providerPath = [ "p" … ], if a node whose label matches that path exists,
  # the sub-aspect is removed and its edges are rewired to the parent. Chains
  # are resolved transitively so nested sub-aspects collapse all the way up.
  foldProviders =
    graph:
    let
      nodeByLabel = lib.listToAttrs (
        map (n: {
          name = n.fullLabel;
          value = n;
        }) graph.nodes
      );
      parentLabelOf = node: lib.concatStringsSep "/" (node.providerPath or [ ]);
      parentIdOf =
        node:
        let
          pl = parentLabelOf node;
        in
        if pl != "" && nodeByLabel ? ${pl} then nodeByLabel.${pl}.id else null;

      rewritePairs = lib.concatMap (
        n:
        if (n.providerPath or [ ]) != [ ] then
          let
            pid = parentIdOf n;
          in
          if pid != null then
            [
              {
                name = n.id;
                value = pid;
              }
            ]
          else
            [ ]
        else
          [ ]
      ) graph.nodes;
      rewriteMap = lib.listToAttrs rewritePairs;

      # Resolve transitively so chains (a → b → c) all fold into c.
      rewireFinal = id: if rewriteMap ? ${id} then rewireFinal rewriteMap.${id} else id;

      keptNodes = builtins.filter (n: !(rewriteMap ? ${n.id})) graph.nodes;
      rewiredEdges = map (
        e:
        e
        // {
          from = rewireFinal e.from;
          to = rewireFinal e.to;
        }
      ) graph.edges;
      keptEdges = dedupBy (e: "${e.from}->${e.to}") (builtins.filter (e: e.from != e.to) rewiredEdges);
    in
    graph
    // {
      nodes = keptNodes;
      edges = keptEdges;
    };

  # Simplified view: user aspects, flat, providers folded into parents.
  simplified = graph: foldProviders (flattenStages (aspectsOnly graph));

  # Providers-only view: reshape the graph as a true provider hierarchy.
  #
  # For each node with `providerPath = [a, b, ..., z]` we emit an edge
  # from the immediate-parent-provider node (the one whose fullLabel is
  # `a/b/.../z`) to this node. The result is a proper multi-level tree
  # rooted at top-level provider aspects, where intermediate nodes like
  # `coolercontrol/class` sit between `coolercontrol` and
  # `coolercontrol/class/enable` instead of a flat fan-out.
  #
  # Answers: "in this host, what does each provider chain actually
  # expand into, layer by layer?"
  providersOnly =
    graph:
    let
      filtered = filterUserAspects graph;
      byFull = lib.listToAttrs (
        map (n: {
          name = n.fullLabel;
          value = n;
        }) filtered.nodes
      );
      providerNodes = builtins.filter (n: (n.providerPath or [ ]) != [ ]) filtered.nodes;
      edgeFor =
        n:
        let
          parentFull = lib.concatStringsSep "/" n.providerPath;
          parent = byFull.${parentFull} or null;
        in
        if parent != null then
          [
            {
              from = parent.id;
              to = n.id;
              style = "normal";
              label = null;
            }
          ]
        else
          [ ];
      treeEdges = lib.concatMap edgeFor providerNodes;
      keptIds = lib.listToAttrs (
        map
          (id: {
            name = id;
            value = true;
          })
          (
            lib.unique (
              lib.concatMap (e: [
                e.from
                e.to
              ]) treeEdges
            )
          )
      );
      keptNodes = builtins.filter (n: keptIds ? ${n.id}) filtered.nodes;
    in
    filtered
    // {
      direction = "TD";
      nodes = keptNodes;
      edges = treeEdges;
      stages = [ ];
      stageEdges = [ ];
    };

  # Predicate-based subset view: keep nodes matching `pred` + their
  # direct graph neighbors (one hop in/out). Used by adapters /
  # parametric / anything that says "show these decorated nodes in
  # context". Stage subgraphs are dropped but each node's own `stage`
  # field is preserved so renderers can decorate the label.
  neighborhoodOf =
    pred: graph:
    let
      filtered = filterUserAspects graph;
      nbhd = neighborhoodByNodes pred filtered;
    in
    nbhd
    // {
      stages = [ ];
      stageEdges = [ ];
    };

  # Adapters view: nodes with style != "default" (i.e. adapter / excluded
  # / replaced) plus immediate neighbors. Empty on configs that don't
  # use `exclude` / `substitute` / `handlers` — that
  # emptiness itself is a useful signal.
  adaptersOnly = graph: neighborhoodOf (n: (n.style or "default") != "default") graph;

  # Parametric aspects view: only aspects that take function arguments
  # (`isParametric = true`). Plus their graph neighbors so the
  # parametric hexagons don't float alone. Good for spotting dynamic
  # configuration points in a config.
  parametricOnly = graph: neighborhoodOf (n: n.isParametric or false) graph;

  # User-declared view: only nodes that carry `hasClass = true` — i.e.
  # aspects a user explicitly wrote, as opposed to plumbing nodes or
  # module-merge artifacts. Cuts out a lot of pipeline noise without
  # going all the way to `simplified`.
  userDeclaredOnly = graph: filterByNodes (n: n.hasClass or false) (filterUserAspects graph);

  # Per-class slice: start from nodes that actively contribute to
  # `className` (perClass.<className>.hasClass == true), then include
  # all ancestors reachable via edges. Result: a subgraph showing
  # every class-<className> contribution AND the organizer/provider
  # aspects that pull them in. Without the ancestor closure the view
  # would be a flat list of leaves, losing the inclusion hierarchy.
  classSlice =
    className: graph:
    ancestorClosureBy (n: n.perClass.${className}.hasClass or false) (filterUserAspects graph);

  # Cross-class view: nodes that contribute to 2+ classes via the
  # perClass attrset (hasClass = true in more than one class). These
  # are the "bridge" aspects spanning nixos + homeManager (or more).
  crossClassOnly =
    graph:
    let
      activeClassCount =
        n:
        builtins.length (
          builtins.filter (c: n.perClass.${c}.hasClass or false) (builtins.attrNames (n.perClass or { }))
        );
    in
    filterByNodes (n: activeClassCount n >= 2) (filterUserAspects graph);

  # hasAspect presence slice: the set of nodes that would answer
  # `entity.hasAspect <ref>` = true for a given class, driven by the
  # host's `collectPathSet` (which this filter reaches via the
  # auxiliary fields threaded by `hostContext` onto the graph record).
  # Path-set keys are slash-joined aspectPaths and match the
  # `fullLabel` form of graph nodes exactly, so membership is an
  # O(1) attrset check with no extra walking.
  #
  # The resulting graph keeps every node that's structurally present
  # (answers true) plus, as "would-return-false" annotations, any
  # tombstoned nodes that sit under the same parents. This gives the
  # hasAspect query surface its native visual: present = default,
  # tombstoned = red-dashed.
  #
  # Ancestor closure keeps the organizer chain visible even when only
  # leaves are structurally present — otherwise the view would be a
  # flat list of leaves and lose its "how did we get here" structure.
  #
  # Callers that already have a pathSet (tests, ad-hoc scripts) use
  # the `-with` variant; normal per-host views just pass `{ class }`
  # and let the filter pull `rootAspect` off the graph record.
  hasAspectPresentWith =
    pathSet: graph:
    let
      filtered = filterUserAspects graph;
      isPresent = n: pathSet ? ${n.pathKey} || isTombstone n;
    in
    ancestorClosureBy isPresent filtered;

  hasAspectPresent =
    { class }:
    graph:
    let
      pathSets =
        graph.pathSets
          or (throw "hasAspectPresent: graph is missing pathSets; build via diag.graph.hostContext, not ofHost.");
      pathSet =
        pathSets.${class}
          or (throw "hasAspectPresent: no pathSet captured for class '${class}'. Known classes: ${lib.concatStringsSep ", " (builtins.attrNames pathSets)}.");
    in
    hasAspectPresentWith pathSet graph;

  # Union of hasAspectPresent across multiple classes: a node is kept
  # if it appears in the presence set of ANY class. Useful for
  # "what can entity.hasAspect.forAnyClass see?" views.
  hasAspectForAnyClass =
    classes: graph:
    let
      perClass = builtins.map (c: hasAspectPresent { class = c; } graph) classes;
      keepIds = lib.foldl' (
        acc: g: lib.foldl' (acc': n: acc' // { ${n.id} = true; }) acc g.nodes
      ) { } perClass;
    in
    filterByNodes (n: keepIds ? ${n.id}) graph;

  # Attribution-based structural-decision view. Groups excluded nodes
  # by their `perClass.<class>.excludedFrom` field — the full
  # aspectPath identity of the user-declared aspect whose
  # `meta.handleWith` caused the tombstone. The constraint-owner node is
  # shown alongside its direct inclusion-children (survivors and
  # tombstones side by side), so the view reads "for each adapter
  # owner, here are the aspects it decided on". Tombstones keep their
  # `excluded` style (red-dashed); survivors show as default.
  #
  # Catches `oneOf`, `exclude`, and any custom
  # meta.handleWith that tombstones via `filterIncludes`.
  decisionsView =
    graph:
    let
      filtered = filterUserAspects graph;

      # Collect all unique adapter-owner names from perClass metadata.
      ownerNames = lib.unique (
        lib.concatMap (
          n:
          lib.concatMap (
            className:
            let
              pc = n.perClass.${className} or { };
              from = pc.excludedFrom or null;
            in
            if pc.excluded or false && from != null then [ from ] else [ ]
          ) (builtins.attrNames (n.perClass or { }))
        ) filtered.nodes
      );

      # Match owner names to graph node IDs.
      ownerIds = lib.unique (
        lib.concatMap (
          oname: lib.concatMap (n: lib.optional (n.fullLabel == oname) n.id) filtered.nodes
        ) ownerNames
      );

      # Tombstoned nodes attributed to any owner.
      tombstoneIds = map (n: n.id) (builtins.filter isTombstone filtered.nodes);

      # Adjacency from inclusion edges only — provider-provenance
      # edges run the opposite direction and would contaminate lookups.
      adj = adjacency (inclusionEdgesOnly filtered.edges);
      childIdsOf = id: adj.outOf.${id} or [ ];
      parentIdsOf = id: adj.inTo.${id} or [ ];

      # For each tombstone, include its inclusion-parent and the
      # parent's other children (surviving siblings) for context.
      # This shows "at the junction where the kill happened, here's
      # what survived and here's what was dropped".
      tombstoneParentIds = lib.unique (lib.concatMap parentIdsOf tombstoneIds);
      siblingIds = lib.unique (lib.concatMap childIdsOf tombstoneParentIds);

      keepIds = lib.unique (ownerIds ++ tombstoneIds ++ tombstoneParentIds ++ siblingIds);
      keepSet = lib.listToAttrs (
        map (id: {
          name = id;
          value = true;
        }) keepIds
      );
      result = filterByNodes (n: keepSet ? ${n.id}) filtered;
    in
    result
    // {
      stages = [ ];
      stageEdges = [ ];
    };

  # Orphans-and-leaves lint view: nodes with no incoming edges that
  # aren't the host itself (orphans — reachability mystery) PLUS nodes
  # with no outgoing edges (leaves — terminal aspects). Useful for
  # spotting dead code and "end of the line" aspects at a glance.
  #
  # Implemented over `filterUserAspects` so only user-visible aspects
  # are candidates — plumbing nodes aren't orphans just because the
  # context wrappers don't point at them.
  orphansAndLeaves =
    graph:
    let
      filtered = filterUserAspects graph;
      adj = adjacency filtered.edges;
      isOrphan = n: !(adj.inTo ? ${n.id}) && n.id != filtered.rootId;
      isLeaf = n: !(adj.outOf ? ${n.id});
      pruned = filterByNodes (n: isOrphan n || isLeaf n) filtered;
    in
    pruned
    // {
      stages = [ ];
      stageEdges = [ ];
    };

  # Graph diff: merge two graphs A and B into a single graph where
  # every node and edge carries an `origin` tag:
  #
  #   "a"    — node/edge is present in A only (removed from B → A)
  #   "b"    — node/edge is present in B only (added going A → B)
  #   "both" — present in both (common / unchanged structure)
  #
  # Keyed by `fullLabel` (for nodes) and `(from, to)` (for edges).
  # The rest of the node/edge record is inherited from whichever side
  # defines it, with A taking precedence when both sides match.
  #
  # Renderers read `node.origin` to color the diff — typically
  # removed = dashed red border, added = thick accent border,
  # both = normal style.
  #
  # Useful for:
  #   - host-vs-host comparison (shared core vs per-host additions)
  #   - pre-adapter vs post-adapter (what did this adapter *do*?)
  #   - class-vs-class overlay (nixos slice vs homeManager slice)
  diff =
    { a, b }:
    let
      nodesA = lib.listToAttrs (
        map (n: {
          name = n.fullLabel;
          value = n;
        }) a.nodes
      );
      nodesB = lib.listToAttrs (
        map (n: {
          name = n.fullLabel;
          value = n;
        }) b.nodes
      );
      allKeys = lib.unique (map (n: n.fullLabel) a.nodes ++ map (n: n.fullLabel) b.nodes);
      taggedNodes = map (
        k:
        let
          inA = nodesA ? ${k};
          inB = nodesB ? ${k};
          source = if inA then nodesA.${k} else nodesB.${k};
        in
        source
        // {
          origin =
            if inA && inB then
              "both"
            else if inA then
              "a"
            else
              "b";
        }
      ) allKeys;

      edgesA = lib.listToAttrs (
        map (e: {
          name = "${e.from}->${e.to}";
          value = e;
        }) a.edges
      );
      edgesB = lib.listToAttrs (
        map (e: {
          name = "${e.from}->${e.to}";
          value = e;
        }) b.edges
      );
      allEdgeKeys = lib.unique (lib.attrNames edgesA ++ lib.attrNames edgesB);
      taggedEdges = map (
        k:
        let
          inA = edgesA ? ${k};
          inB = edgesB ? ${k};
          source = if inA then edgesA.${k} else edgesB.${k};
        in
        source
        // {
          origin =
            if inA && inB then
              "both"
            else if inA then
              "a"
            else
              "b";
        }
      ) allEdgeKeys;
    in
    a
    // {
      nodes = taggedNodes;
      edges = taggedEdges;
      # Stages/stageEdges kept from A as a baseline; diff is about
      # aspect structure, not about changing the stage pipeline.
      stages = a.stages or [ ];
      stageEdges = a.stageEdges or [ ];
    };

  # Pipeline meta view: keep ONLY wrapper/plumbing nodes, dropping all
  # user-facing aspects. Reveals how a single aspect flows through the
  # resolution machinery — `aspect(class) → self-provide → cross-provide
  # → resolve` — at the trace level. Useful for debugging adapter
  # composition.
  pipelineOnly = graph: filterByNodes (n: isWrapper n.label) (filterMeaningful graph);

  # Fan-in / fan-out metrics: for each node, count how many edges
  # point at it (fan-in, reuse count) and how many it originates
  # (fan-out, orchestrator score). Returns a list of records
  # `{ id, label, fullLabel, stage, class, fanIn, fanOut, total }`
  # sorted by `total` descending. Consumed by sankey/treemap renderers
  # to build weighted flows.
  fanMetrics =
    graph:
    let
      filtered = filterUserAspects graph;
      inCounts = lib.foldl' (acc: e: acc // { ${e.to} = (acc.${e.to} or 0) + 1; }) { } filtered.edges;
      outCounts = lib.foldl' (
        acc: e: acc // { ${e.from} = (acc.${e.from} or 0) + 1; }
      ) { } filtered.edges;
    in
    lib.sort (a: b: a.total > b.total) (
      map (
        n:
        let
          fanIn = inCounts.${n.id} or 0;
          fanOut = outCounts.${n.id} or 0;
        in
        {
          inherit (n)
            id
            label
            fullLabel
            stage
            class
            ;
          inherit fanIn fanOut;
          total = fanIn + fanOut;
        }
      ) filtered.nodes
    );
in
{
  inherit
    filterMeaningful
    filterUserAspects
    foldWrappers
    foldProviders
    flattenStages
    simplified
    contextOnly
    aspectsOnly
    providersOnly
    neighborhoodOf
    adaptersOnly
    parametricOnly
    userDeclaredOnly
    classSlice
    crossClassOnly
    hasAspectPresent
    hasAspectPresentWith
    hasAspectForAnyClass
    decisionsView
    orphansAndLeaves
    diff
    pipelineOnly
    fanMetrics
    ;
}
