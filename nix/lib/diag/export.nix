# Export helpers: turn view definitions into derivation entries.
#
# Each helper produces a list of `{ name, view, ext, tool, drv }`
# records that templates iterate to build packages and files.
#
# Templates compose these with their own gallery/README builders:
#
#   entries = diag.export.ofViews { inherit pkgs rc; }
#     allHosts hostViewDefs fleetData fleetViewDefs;
#
{ lib }:
let
  # --- Naming conventions ---

  # File name: <name>-<view>[.<tool>].<ext>
  entryFileName =
    e:
    let
      base = "${e.name}-${e.view}";
      toolInfix = if e.tool != null then ".${e.tool}" else "";
    in
    "${base}${toolInfix}.${e.ext}";

  # Package name: <name>-<view>[-<tool>][-<ext>] (nix-safe)
  entryPackageName =
    e:
    let
      base = "${e.name}-${e.view}";
      toolSuffix = if e.tool != null then "-${e.tool}" else "";
      extSuffix = if e.ext == "svg" then "-svg" else "";
    in
    "${base}${toolSuffix}${extSuffix}";

  entryRelPath = e: "diagrams/${entryFileName e}";

  # --- Md wrapper builders ---

  mkViewMd =
    pkgs:
    {
      base,
      title,
      entityName,
      altText,
      svgInfix,
      mdLang,
      source,
    }:
    let
      imageEmbed = if svgInfix == null then "" else "![${altText}](./${base}.${svgInfix}.svg)\n\n";
    in
    pkgs.writeText "${base}.md" ''
      # ${title}: ${entityName}

      ${imageEmbed}```${mdLang}
      ${source}
      ```
    '';

  mkFleetMd =
    pkgs:
    {
      base,
      title,
      altText,
      svgInfix,
      mdLang,
      source,
    }:
    pkgs.writeText "${base}.md" ''
      # ${title}

      ![${altText}](./${base}.${svgInfix}.svg)

      ```${mdLang}
      ${source}
      ```
    '';

  # --- Entry builders ---

  # Single view → [md entry, svg entry?]
  mkViewEntries =
    pkgs: entityName: graph: view:
    let
      source = view.compute graph;
      base = "${entityName}-${view.view}";
      mdDrv = mkViewMd pkgs {
        inherit base source;
        title = view.title;
        inherit entityName;
        inherit (view) altText svgInfix mdLang;
      };
      mdEntry = {
        name = entityName;
        view = view.view;
        ext = "md";
        tool = null;
        drv = mdDrv;
      };
      svgEntry = {
        name = entityName;
        view = view.view;
        ext = "svg";
        tool = view.svgInfix;
        drv = view.svgFn base source;
      };
    in
    [ mdEntry ] ++ lib.optional (view.svgFn != null) svgEntry;

  # Multi-format DAG view: one md embedding three SVGs.
  mkDagEntries =
    pkgs: rc: entityName: graph:
    let
      mmdSrc = rc.renderDense.toMermaid graph;
      dotSrc = rc.render.toDot graph;
      pumlSrc = rc.render.toPlantUML graph;
      base = "${entityName}-dag";
      mdDrv = pkgs.writeText "${base}.md" ''
        # Full DAG: ${entityName}

        ## Mermaid

        ![Mermaid render](./${base}.mmd.svg)

        ```mermaid
        ${mmdSrc}
        ```

        ## Graphviz DOT

        ![DOT render](./${base}.dot.svg)

        ```dot
        ${dotSrc}
        ```

        ## PlantUML

        ![PlantUML render](./${base}.puml.svg)

        ```plantuml
        ${pumlSrc}
        ```
      '';
    in
    [
      {
        name = entityName;
        view = "dag";
        ext = "md";
        tool = null;
        drv = mdDrv;
      }
      {
        name = entityName;
        view = "dag";
        ext = "svg";
        tool = "mmd";
        drv = rc.mmdSourceToSvg base mmdSrc;
      }
      {
        name = entityName;
        view = "dag";
        ext = "svg";
        tool = "dot";
        drv = rc.dotSourceToSvg base dotSrc;
      }
      {
        name = entityName;
        view = "dag";
        ext = "svg";
        tool = "puml";
        drv = rc.pumlSourceToSvg base pumlSrc;
      }
    ];

  # Fleet view → [md entry, svg entry]
  mkFleetViewEntries =
    pkgs: fleetData: view:
    let
      source = view.compute fleetData;
      base = "fleet-${view.view}";
      mdDrv = mkFleetMd pkgs {
        inherit base source;
        title = view.title;
        inherit (view) altText svgInfix mdLang;
      };
      svgDrv = view.svgFn base source;
    in
    [
      {
        name = "fleet";
        view = view.view;
        ext = "md";
        tool = null;
        drv = mdDrv;
      }
      {
        name = "fleet";
        view = view.view;
        ext = "svg";
        tool = view.svgInfix;
        drv = svgDrv;
      }
    ];

  # --- Batch builders ---

  # All entries for one entity (views + dag + optional gallery entry).
  entityEntries =
    {
      pkgs,
      rc,
      diag,
    }:
    {
      entity,
      name,
      viewDefs,
      galleryDrv ? null,
    }:
    let
      g = if entity ? nodes then entity else diag.hostContext { host = entity; };
    in
    lib.concatMap (mkViewEntries pkgs name g) viewDefs
    ++ mkDagEntries pkgs rc name g
    ++ lib.optional (galleryDrv != null) {
      inherit name;
      view = "gallery";
      ext = "md";
      tool = null;
      drv = galleryDrv;
    };

  # All fleet entries (views + optional gallery entry).
  fleetEntries =
    { pkgs }:
    {
      fleetData,
      viewDefs,
      galleryDrv ? null,
    }:
    lib.concatMap (mkFleetViewEntries pkgs fleetData) viewDefs
    ++ lib.optional (galleryDrv != null) {
      name = "fleet";
      view = "gallery";
      ext = "md";
      tool = null;
      drv = galleryDrv;
    };

  # Convert a list of entries to a packages attrset.
  entriesToPackages =
    entries:
    lib.listToAttrs (
      map (e: {
        name = entryPackageName e;
        value = e.drv;
      }) entries
    );

  # Convert entries to files records (for the `files` flake module).
  entriesToFiles =
    entries:
    map (e: {
      path_ = entryRelPath e;
      inherit (e) drv;
    }) entries;

  # Shell script line that copies one entry to the output dir.
  entryCopyLine = e: ''cat ${e.drv} > "$dest/${entryRelPath e}"'';

in
{
  inherit
    mkViewEntries
    mkDagEntries
    mkFleetViewEntries
    entityEntries
    fleetEntries
    entriesToPackages
    entriesToFiles
    entryCopyLine
    entryFileName
    entryPackageName
    entryRelPath
    ;
}
