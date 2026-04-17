# Reshape — synthesize alternative graph structures from the base graph.
{
  lib,
  util,
  graphLib,
  filterByNodes,
  filterUserAspects,
}:
let
  inherit (graphLib) emptyNode;
in
{
  # Context hierarchy only: reshape the graph so the context pipeline stages
  # become the nodes. Aspect content is discarded. The host node is retained
  # and connected to entry stages (those with no incoming stage transition)
  # so the rendered graph reads "host -> first stage -> ...".
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

  # Providers-only view: reshape the graph as a true provider hierarchy.
  #
  # For each node with `providerPath = [a, b, ..., z]` we emit an edge
  # from the immediate-parent-provider node (the one whose fullLabel is
  # `a/b/.../z`) to this node. The result is a proper multi-level tree
  # rooted at top-level provider aspects.
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

  # Attribution-based structural-decision view. Groups excluded nodes
  # by their `perClass.<class>.excludedFrom` field. The constraint-owner
  # node is shown alongside its direct inclusion-children (survivors and
  # tombstones side by side).
  decisionsView =
    graph:
    let
      filtered = filterUserAspects graph;
      inclusionEdgesOnly = edges: builtins.filter (e: (e.style or "normal") != "provide") edges;

      inherit (util) adjacency isTombstone;

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

      # Adjacency from inclusion edges only.
      adj = adjacency (inclusionEdgesOnly filtered.edges);
      childIdsOf = id: adj.outOf.${id} or [ ];
      parentIdsOf = id: adj.inTo.${id} or [ ];

      # For each tombstone, include its inclusion-parent and the
      # parent's other children (surviving siblings) for context.
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
}
