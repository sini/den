# Diagram library.
#
# Composable pipeline for rendering aspect-resolution graphs as many
# diagram formats (Mermaid, Graphviz DOT, PlantUML, C4):
#
#   1. trace capture      — collect structuredTrace entries from an aspect
#   2. graph construction — build a format-agnostic IR from those entries
#   3. filtering          — prune and fold the IR
#   4. rendering          — emit Mermaid / DOT / PlantUML strings
#
# Called via `den.lib.diag` from templates and ad-hoc scripts.
#
# ## API layout
#
#   diag.graph.*    — graph IR construction + filters (data)
#   diag.fleet.*    — fleet-wide graph construction
#   diag.capture*   — structured-trace capture
#   diag.theme*     — theme records from base16 palettes
#   diag.toMermaid  — renderers (and all `to<Foo>` variants)
#   diag.renderers  — pre-configured renderer set constructor
#
# ## One-call convenience for the common host case
#
#   g = diag.hostContext { inherit host; };
#   rendered = diag.toMermaid (diag.graph.filterUserAspects g);
#
# ## Generic form (any den.ctx.* entity kind)
#
#   root = den.ctx.user { inherit host user; };
#   g = diag.context { inherit root; name = user.name; classes = [ "homeManager" ]; };
#
# ## Pipeline form for finer control
#
#   root = den.ctx.host { inherit host; };
#   entries = diag.captureAll [ "nixos" "homeManager" ] root;
#   g = diag.graph.build {
#     inherit entries;
#     rootName = host.name;
#     ctxTrace = root.__ctxTrace or [ ];
#   };
#
{ lib, den, ... }:
let
  util = import ./util.nix { inherit lib; };
  colors = import ./colors.nix { inherit lib; };
  themes = import ./themes.nix { inherit lib; };
  renderUtil = import ./render-util.nix { inherit lib themes; };
  capture = import ./capture.nix { inherit den lib; };
  graphLib = import ./graph.nix { inherit lib util; };
  filtersLib = import ./filters.nix { inherit lib util graphLib; };
  mermaid = import ./mermaid.nix {
    inherit
      lib
      themes
      colors
      util
      renderUtil
      ;
  };
  dot = import ./dot.nix {
    inherit
      lib
      themes
      colors
      util
      renderUtil
      ;
  };
  plantuml = import ./plantuml.nix {
    inherit
      lib
      themes
      colors
      util
      renderUtil
      ;
  };
  sequence = import ./sequence.nix {
    inherit
      lib
      themes
      util
      renderUtil
      ;
  };
  c4 = import ./c4.nix {
    inherit
      lib
      themes
      util
      renderUtil
      ;
  };
  sankey = import ./sankey.nix {
    inherit
      lib
      themes
      util
      renderUtil
      ;
  };
  treemap = import ./treemap.nix { inherit lib themes renderUtil; };
  mindmap = import ./mindmap.nix {
    inherit
      lib
      themes
      util
      renderUtil
      ;
  };
  state = import ./state.nix {
    inherit
      lib
      themes
      util
      renderUtil
      ;
  };
  fleetLib = import ./fleet.nix { inherit den lib; };
  exportLib = import ./export.nix { inherit lib; };

  # --- Entity-agnostic context constructor ---
  #
  # Build a graph IR from any pre-resolved aspect root (host, user,
  # home, or custom entity kind). The caller resolves the entity
  # via `den.ctx.<kind> { ... }` and passes the result as `root`.
  #
  # Returns a graph IR with auxiliary fields merged in:
  #
  #   rootAspect — the resolved aspect (for ad-hoc queries)
  #   classes    — the list of classes the capture used
  #   pathSets   — `{ <class> = toPathSet [...]; }`, one per class,
  #                pre-computed so hasAspect-driven filters don't
  #                need a second resolve pass
  #
  # Every filter in `filters.nix` accepts the result directly (it
  # IS-A graph). The auxiliary fields are additive and free unless
  # consumed (nix laziness).
  context =
    {
      root, # resolved aspect from den.ctx.<kind> { ... }
      name, # display name for the graph root badge
      classes, # which classes to capture
      direction ? "LR",
    }:
    let
      captured = capture.captureWithPaths classes root;
      graph = graphLib.buildGraph {
        entries = captured.entries;
        rootName = name;
        ctxTrace = root.__ctxTrace or [ ];
        inherit direction;
      };
      pathSets = captured.pathsByClass;
    in
    graph
    // {
      rootAspect = root;
      inherit pathSets classes;
    };

  # --- Host convenience wrapper ---
  #
  # Resolves `den.ctx.host { inherit host; }`, auto-discovers classes
  # from the host's users, and delegates to `diag.context`. This is
  # the entry point for the common case; for other entity kinds (user,
  # home, custom), call `diag.context` directly.
  hostContext =
    {
      host,
      classes ? null,
      direction ? "LR",
    }:
    let
      userClasses = lib.unique (lib.concatMap (u: u.classes or [ ]) (lib.attrValues (host.users or { })));
      actualClasses =
        if classes != null then
          classes
        else
          lib.unique (
            [
              "nixos"
              "homeManager"
              "user"
            ]
            ++ userClasses
          );
      root = den.ctx.host { inherit host; };
    in
    context {
      inherit root direction;
      name = host.name;
      classes = actualClasses;
    };

  # --- User convenience wrapper ---
  #
  # Resolves `den.ctx.user { inherit host user; }`, auto-discovers classes
  # from the user entity, and delegates to `diag.context`.
  userContext =
    {
      host,
      user,
      classes ? null,
      direction ? "LR",
    }:
    let
      actualClasses =
        if classes != null then
          classes
        else
          lib.unique (
            [
              "homeManager"
              "user"
            ]
            ++ (user.classes or [ "homeManager" ])
          );
      root = den.ctx.user { inherit host user; };
    in
    context {
      inherit root direction;
      name = user.name;
      classes = actualClasses;
    };

  # --- Home convenience wrapper ---
  #
  # Resolves `den.ctx.home { inherit home; }`, auto-discovers classes
  # from the home entity, and delegates to `diag.context`.
  homeContext =
    {
      home,
      classes ? null,
      direction ? "LR",
    }:
    let
      actualClasses =
        if classes != null then
          classes
        else
          lib.unique ([ "homeManager" ] ++ (home.classes or [ "homeManager" ]));
      root = den.ctx.home { inherit home; };
    in
    context {
      inherit root direction;
      name = home.name;
      classes = actualClasses;
    };

  # Thin wrapper returning a plain graph (no auxiliary fields).
  graphOfHost =
    args:
    removeAttrs (hostContext args) [
      "rootAspect"
      "pathSets"
      "classes"
    ];

  # Build a graph from the raw `den.aspects` namespace — declarations
  # only, no host resolution. This is an orthogonal data path to
  # `ofHost`: instead of tracing what a particular host WOULD activate,
  # it shows what the library ACTUALLY DEFINES, host-independent.
  #
  # Only the static subset of each aspect is walkable without context:
  #
  #   - `includes = [ <static refs> ]`   → edges (resolved via aspectPath)
  #   - `includes = <functor>`           → marked "dynamic", no edges
  #   - `meta.provider` chain            → grouping into provider clusters
  #   - `meta.adapter` presence          → flag node as decision-owner
  #
  # Limitations vs ofHost:
  #
  #   - parametric / functor includes don't fire, so dynamically-assembled
  #     graphs appear as terminals with a "dynamic" annotation
  #   - `provides = { foo = ...; }` cross-provider relationships aren't
  #     walked (no host means no prev/ctx chain)
  #   - class selection (nixos vs homeManager) is irrelevant — every
  #     aspect is shown once
  #
  # The view answers: "given the library, what are the authored building
  # blocks and how do their static inclusions compose?" Intended for docs,
  # library audits, and spotting orphan aspects that nothing references.
  namespaceGraph =
    {
      name ? "aspects",
      aspects ? den.aspects or { },
      direction ? "TD",
      # Optional predicate applied after the "is it an aspect record"
      # check. Lets callers slice to e.g. adapter-owning aspects,
      # parametric aspects, a provider subtree, etc., without writing
      # a fresh walker. See the view catalog for examples.
      filter ? (_: true),
    }:
    let
      sanitize = util.makeIdSanitizer "ns";
      # `den.aspects.<k>` may be a user-declared aspect (attrset with
      # name/includes/meta) OR an internal nested namespace carrying
      # sub-aspects. Require `meta` to tighten the heuristic against
      # stray attrsets that happen to have `name`/`includes` fields.
      isAspect =
        v: builtins.isAttrs v && v ? includes && v ? name && v ? meta && builtins.isAttrs (v.meta or null);
      entries = lib.filterAttrs (_: v: isAspect v && filter v) aspects;
      aspectNames = builtins.attrNames entries;

      # Match a value inside `includes` to a top-level namespace key.
      # Static include shapes we can resolve:
      #   - direct aspect reference: `aspects.foo` → `foo`
      #   - angle-bracket sugar after findFile: same shape as direct ref
      # Everything else (functors, { includes = fn }, plain attrsets)
      # is classified as dynamic and gets no edge.
      refToName =
        ref:
        if !builtins.isAttrs ref then
          null
        else if ref ? name && entries ? ${ref.name} then
          ref.name
        else
          null;

      # Static includes only. Functors and inline anonymous aspect
      # definitions are not walked.
      staticIncludes =
        value:
        let
          incs = value.includes or [ ];
        in
        if builtins.isList incs then incs else [ ];

      mkNode =
        name: value:
        let
          incs = staticIncludes value;
          hasFunctorInclude = lib.any (i: !builtins.isAttrs i) incs;
          hasAdapter = (value.meta.adapter or null) != null;
          hasProvides = (value.provides or { }) != { };
          providerChain = value.meta.provider or [ ];
        in
        graphLib.emptyNode
        // {
          id = sanitize name;
          label = name;
          fullLabel = name;
          # Shape: parametric-ish if dynamic-includes; provider-ish if
          # it provides child aspects; default otherwise. Mirrors
          # buildGraph's `nodeShape` so renderers can reuse the same
          # color / shape classifications.
          shape =
            if hasFunctorInclude then
              "hexagon"
            else if hasProvides then
              "trapezoid"
            else
              "rect";
          style = if hasAdapter then "adapter" else "default";
          providerPath = providerChain;
          hasClass = true;
        };

      mkEdges =
        name: value:
        let
          incs = staticIncludes value;
          fromId = sanitize name;
        in
        lib.concatMap (
          i:
          let
            target = refToName i;
          in
          lib.optional (target != null && target != name) {
            from = fromId;
            to = sanitize target;
            style = "normal";
            label = null;
          }
        ) incs;

      allNodes = lib.mapAttrsToList mkNode entries;
      declEdges = lib.concatMap (n: mkEdges n entries.${n}) aspectNames;

      # Mermaid-family renderers always draw a host badge at the top
      # (see mermaid.nix::nodeDecl). For the namespace view we keep
      # that badge meaningful by connecting it to true "roots" —
      # aspects that nothing else statically includes — so the badge
      # reads as "entry points for this library" rather than an
      # orphaned title box. Aspects included transitively still find
      # their parents via `declEdges`; they just don't get a direct
      # edge from the host badge.
      rootId = sanitize name;
      includedTargets = lib.listToAttrs (
        map (e: {
          name = e.to;
          value = true;
        }) declEdges
      );
      rootEdges = lib.concatMap (
        aname:
        let
          nid = sanitize aname;
        in
        lib.optional (!(includedTargets ? ${nid})) {
          from = rootId;
          to = nid;
          style = "normal";
          label = null;
        }
      ) aspectNames;
    in
    {
      rootName = name;
      inherit rootId direction;
      nodes = allNodes;
      edges = rootEdges ++ declEdges;
      stages = [ ];
      stageEdges = [ ];
    };

  # `diag.graph.*` — graph IR construction + filters. Every filter
  # operates on any graph record regardless of entity kind.
  graph = {
    build = graphLib.buildGraph;
    ofHost = graphOfHost;
    ofNamespace = namespaceGraph;
  }
  // filtersLib;

  # `diag.fleet.*` — fleet-level graph construction.
  fleet = {
    of = fleetLib.fleetGraph;
  };

  # Standard view definitions. Promoted into the lib for
  # discoverability — templates call `diag.views.host { ... }` to get
  # the standard set, then extend or filter as needed.
  views = import ./views.nix { inherit graph toJSON; };

  # Pre-configured renderer set. Callers that render many views against
  # the same theme/config don't need to bake `*With { inherit theme; }` for
  # every renderer — just build the set once and call members by name:
  #
  #   R = diag.renderers { inherit theme; };
  #   Relk = diag.renderers { inherit theme; mermaidConfig = elkCfg; };
  #   ...
  #   R.toSequenceMermaid g
  #   Relk.toMermaid (diag.graph.contextOnly g)
  #
  # C4 / DOT / plantuml renderers don't take mermaidConfig, so it's
  # silently ignored by them; mermaid-family renderers all accept it.
  renderers =
    {
      theme ? themes.defaultTheme,
      mermaidConfig ? { },
    }:
    {
      toMermaid = mermaid.toMermaidWith { inherit theme mermaidConfig; };
      toSequenceMermaid = sequence.toSequenceMermaidWith { inherit theme mermaidConfig; };
      toSequenceMermaidExpanded = sequence.toSequenceMermaidExpandedWith { inherit theme mermaidConfig; };
      toSankeyMermaid = sankey.toSankeyMermaidWith { inherit theme mermaidConfig; };
      toTreemapMermaid = treemap.toTreemapMermaidWith { inherit theme mermaidConfig; };
      toC4Container = c4.toC4ContainerWith { inherit theme; };
      toC4Component = c4.toC4ComponentWith { inherit theme; };
      toC4Context = c4.toC4ContextWith { inherit theme; };
      toC4ContainerMermaid = c4.toC4ContainerMermaidWith { inherit theme mermaidConfig; };
      toC4ComponentMermaid = c4.toC4ComponentMermaidWith { inherit theme mermaidConfig; };
      toC4ContextMermaid = c4.toC4ContextMermaidWith { inherit theme mermaidConfig; };
      toDot = dot.toDotWith { inherit theme; };
      toPlantUML = plantuml.toPlantUMLWith { inherit theme; };
      toFleetSankeyMermaid = sankey.toFleetSankeyMermaidWith { inherit theme mermaidConfig; };
      toFleetTreemapMermaid = treemap.toFleetTreemapMermaidWith { inherit theme mermaidConfig; };
      toFleetProviderMatrix = treemap.toFleetProviderMatrixWith { inherit theme mermaidConfig; };
      toMindmapMermaid = mindmap.toMindmapMermaidWith { inherit theme mermaidConfig; };
      toStateMermaid = state.toStateMermaidWith { inherit theme mermaidConfig; };
      toFanMetricsSankey = sankey.toFanMetricsSankeyWith { inherit theme mermaidConfig; };
      toJSON = toJSON;
    };

  # JSON export of the graph IR. Usable by external tools, test
  # assertions, or future web viewers. Pretty-prints `builtins.toJSON`
  # onto a reasonable subset of the node/edge schema — drops fields
  # that can't round-trip (e.g. function refs).
  toJSON =
    graph:
    let
      sanitizeNode =
        n:
        {
          inherit (n)
            id
            label
            fullLabel
            pathKey
            shape
            style
            stage
            classes
            class
            isParametric
            isProvider
            providerPath
            hasClass
            ;
          inherit (n) fnArgNames;
          perClass = n.perClass or { };
        }
        // lib.optionalAttrs (n ? origin) { inherit (n) origin; };
      sanitizeEdge =
        e:
        {
          inherit (e)
            from
            to
            style
            label
            ;
        }
        // lib.optionalAttrs (e ? origin) { inherit (e) origin; };
    in
    builtins.toJSON {
      rootName = graph.rootName or "";
      rootId = graph.rootId or "";
      direction = graph.direction or "LR";
      nodes = map sanitizeNode (graph.nodes or [ ]);
      edges = map sanitizeEdge (graph.edges or [ ]);
      stages = graph.stages or [ ];
      stageEdges = graph.stageEdges or [ ];
    };
  # --- Render context factory ---
  #
  # Builds a single record carrying everything needed to render views:
  # pre-configured renderer sets (`R`, `Rdense`) and the SVG builder
  # functions (`mmdSourceToSvg`, `pumlSourceToSvg`, `dotSourceToSvg`).
  #
  # Templates build one and pass it to `diag.views.host rc`,
  # `diag.views.fleet rc`, and the entry mapper:
  #
  #   rc = diag.renderContext { inherit pkgs theme; mermaidConfig = elkCfg; };
  #   hostViewDefs = diag.views.host rc;
  #
  # Everything is overridable: font packages, CSS font family, mermaid
  # CLI package, and the ELK/dense layout config.
  renderContext =
    {
      pkgs,
      theme ? themes.defaultTheme,
      # Mermaid config for the "dense" renderer set (flowcharts with
      # ELK layout). Pass `{}` to use mermaid defaults.
      mermaidConfig ? { },
      mermaidCli ? pkgs.mermaid-cli,
      renderFonts ? [
        pkgs.jetbrains-mono
        pkgs.fira-code
        pkgs.dejavu_fonts
        pkgs.liberation_ttf
        pkgs.noto-fonts
      ],
      fontFamily ? "JetBrains Mono, Fira Code, DejaVu Sans Mono, monospace",
    }:
    let
      infra = renderInfra {
        inherit
          pkgs
          theme
          renderFonts
          fontFamily
          mermaidCli
          ;
      };
      render = renderers { inherit theme; };
      renderDense = renderers { inherit theme mermaidConfig; };
      rc = infra // {
        inherit render renderDense theme;
        views = {
          core = views.core rc;
          host = views.host rc;
          user = views.user rc;
          home = views.home rc;
          fleet = views.fleet rc;
        };
      };
    in
    rc;

  # Low-level render infrastructure (SVG builders only, no renderer
  # sets). Use `renderContext` instead for the full bundle.
  renderInfra =
    {
      pkgs,
      theme ? themes.defaultTheme,
      renderFonts ? [
        pkgs.jetbrains-mono
        pkgs.fira-code
        pkgs.dejavu_fonts
        pkgs.liberation_ttf
        pkgs.noto-fonts
      ],
      fontFamily ? "JetBrains Mono, Fira Code, DejaVu Sans Mono, monospace",
      mermaidCli ? pkgs.mermaid-cli,
    }:
    let
      renderFontsConf = pkgs.makeFontsConf { fontDirectories = renderFonts; };
      renderFontEnv = ''
        export HOME=$TMPDIR
        export XDG_CACHE_HOME=$TMPDIR/.cache
        export XDG_CONFIG_HOME=$TMPDIR/.config
        mkdir -p "$XDG_CACHE_HOME/fontconfig" "$XDG_CONFIG_HOME/fontconfig"
      '';

      mmdPuppeteerConfig = pkgs.writeText "puppeteer-config.json" (
        builtins.toJSON {
          args = [
            "--no-sandbox"
            "--disable-dev-shm-usage"
          ];
        }
      );
      mmdConfig = pkgs.writeText "mermaid-config.json" (
        builtins.toJSON {
          maxTextSize = 10000000;
          maxEdges = 100000;
          inherit fontFamily;
          securityLevel = "loose";
        }
      );

      mmdSourceToSvg =
        baseName: source:
        let
          src = pkgs.writeText "${baseName}.mmd" source;
        in
        pkgs.runCommand "${baseName}.mmd.svg"
          {
            buildInputs = renderFonts;
            FONTCONFIG_FILE = renderFontsConf;
          }
          ''
            ${renderFontEnv}
            if ${mermaidCli}/bin/mmdc \
                  -i ${src} \
                  -o "$TMPDIR/out.svg" \
                  -p ${mmdPuppeteerConfig} \
                  -c ${mmdConfig} \
                  -b '${theme.background}' \
                  -q 2>"$TMPDIR/mmd-err"; then
              cp "$TMPDIR/out.svg" "$out"
            else
              echo "mermaid-cli failed for ${baseName}:" >&2
              cat "$TMPDIR/mmd-err" >&2 || true
              cat > $out <<'PLACEHOLDER_EOF'
            <?xml version="1.0" encoding="UTF-8"?>
            <svg xmlns="http://www.w3.org/2000/svg" width="720" height="100" viewBox="0 0 720 100">
              <rect width="720" height="100" fill="#fff8e1" stroke="#b08930" stroke-width="2"/>
              <text x="20" y="40" font-family="sans-serif" font-size="14" font-weight="bold" fill="#b05060">
                Mermaid render unavailable
              </text>
              <text x="20" y="64" font-family="sans-serif" font-size="12" fill="#5a5a5a">
                This diagram type may require a newer mermaid than available.
              </text>
              <text x="20" y="82" font-family="monospace" font-size="11" fill="#666">
                See source in the accompanying .md file.
              </text>
            </svg>
            PLACEHOLDER_EOF
            fi
          '';

      pumlSourceToSvg =
        baseName: source:
        let
          src = pkgs.writeText "${baseName}.puml" source;
        in
        pkgs.runCommand "${baseName}.puml.svg"
          {
            buildInputs = renderFonts;
            FONTCONFIG_FILE = renderFontsConf;
          }
          ''
            ${renderFontEnv}
            ${pkgs.plantuml}/bin/plantuml -tsvg -pipe < ${src} > $out
          '';

      dotSourceToSvg =
        base: source:
        let
          src = pkgs.writeText "${base}.dot" source;
        in
        pkgs.runCommand "${base}.dot.svg"
          {
            buildInputs = renderFonts;
            FONTCONFIG_FILE = renderFontsConf;
          }
          ''
            ${renderFontEnv}
            ${pkgs.graphviz}/bin/dot -Tsvg -o $out ${src}
          '';
    in
    {
      inherit
        renderFonts
        renderFontsConf
        mmdSourceToSvg
        pumlSourceToSvg
        dotSourceToSvg
        ;
    };

in
{
  inherit
    context
    hostContext
    userContext
    homeContext
    graph
    fleet
    views
    renderers
    renderContext
    renderInfra
    toJSON
    ;
  export = exportLib;

  inherit (colors) nodeColor nodeColorFor;
  inherit (themes)
    paletteFromBase16
    themeFromPalette
    themeFromBase16
    defaultTheme
    ;
  inherit (capture) capture captureAll captureWithPaths;
  inherit (mermaid) toMermaid toMermaidWith;
  inherit (dot) toDot toDotWith;
  inherit (plantuml) toPlantUML toPlantUMLWith;
  inherit (sequence)
    toSequenceMermaid
    toSequenceMermaidWith
    toSequenceMermaidExpanded
    toSequenceMermaidExpandedWith
    ;
  inherit (c4)
    toC4Component
    toC4ComponentWith
    toC4Container
    toC4ContainerWith
    toC4Context
    toC4ContextWith
    toC4ComponentMermaid
    toC4ComponentMermaidWith
    toC4ContainerMermaid
    toC4ContainerMermaidWith
    toC4ContextMermaid
    toC4ContextMermaidWith
    ;
  inherit (sankey)
    toSankeyMermaid
    toSankeyMermaidWith
    toFleetSankeyMermaid
    toFleetSankeyMermaidWith
    ;
  inherit (treemap)
    toTreemapMermaid
    toTreemapMermaidWith
    toFleetTreemapMermaid
    toFleetTreemapMermaidWith
    toFleetProviderMatrix
    toFleetProviderMatrixWith
    ;
  inherit (mindmap) toMindmapMermaid toMindmapMermaidWith;
  inherit (state) toStateMermaid toStateMermaidWith;
  inherit (sankey) toFanMetricsSankey toFanMetricsSankeyWith;
}
