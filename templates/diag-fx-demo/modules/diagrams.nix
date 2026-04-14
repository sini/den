# Aspect resolution diagrams.
#
# Top-level module. Imports the split sub-files:
#
#   render-infra.nix  — mmdc / plantuml / dot render helpers
#   view-catalog.nix  — hostViewDefs / fleetViewDefs data tables
#   entries.nix       — per-host + fleet entry mapping (md + svg drvs)
#
# Wires them together with the flake inputs (`diag`, `pkgs`, `self`),
# builds the gallery + README derivations, and publishes the
# `packages` + `files.files` attributes that the flake consumes.
{
  den,
  lib,
  self,
  ...
}:
let
  inherit (den.lib) diag;

  allHosts = lib.concatMap builtins.attrValues (builtins.attrValues den.hosts);

  # Base16 scheme name used for all rendered views. Defaults to `github`
  # (a clean light palette); the demo overrides to `catppuccin-mocha`
  # to show off a dark scheme. Users can pick any scheme name that
  # exists in `pkgs.base16-schemes/share/themes/<name>.yaml`.
  themeScheme = "catppuccin-mocha";

in
{
  perSystem =
    { pkgs, ... }:
    let
      # Resolve the base16 scheme into a full theme record. Happens
      # inside perSystem because `paletteFromBase16` needs `pkgs`
      # (shells out to `yj` at build time to convert YAML → JSON).
      theme = diag.themeFromBase16 {
        inherit pkgs;
        scheme = themeScheme;
      };

      # Patched mermaid-cli: swap bundled mermaid@11.12.0 for 11.14.0
      # so ishikawa-beta / treemap-beta / recent diagram types render.
      # Drop this once nixpkgs bundles mermaid ≥11.14.
      mermaidCliPatched = pkgs.mermaid-cli.overrideAttrs (old: {
        postInstall = (old.postInstall or "") + ''
          mermaid_dir="$out/lib/node_modules/@mermaid-js/mermaid-cli/node_modules/mermaid"
          if [ ! -d "$mermaid_dir" ]; then
            echo "mermaidCliPatched: expected $mermaid_dir to exist." >&2
            exit 1
          fi
          rm -rf "$mermaid_dir"
          mkdir -p "$mermaid_dir"
          ${pkgs.gnutar}/bin/tar -xzf ${
            pkgs.fetchurl {
              url = "https://registry.npmjs.org/mermaid/-/mermaid-11.14.0.tgz";
              hash = "sha256-Y7oGZJ4X4Q/uAuVMfC7az+JQtLvds8JJfwDToypC5cc=";
            }
          } -C "$mermaid_dir" --strip-components=1
        '';
      });

      # Render context: renderers + SVG builders + pre-bound views.
      rc = diag.renderContext {
        inherit pkgs theme;
        mermaidCli = mermaidCliPatched;
        mermaidConfig = {
          layout = "elk";
          elk = {
            mergeEdges = true;
            nodePlacementStrategy = "BRANDES_KOEPF";
          };
        };
      };

      # Fleet graph: single data record for flake-wide views.
      fleetData = diag.fleet.of { flakeName = "diag-fx-demo"; };

      # Views from the render context. Extend or filter as needed.
      hostViewDefs = rc.views.host;
      userViewDefs = rc.views.user;
      homeViewDefs = rc.views.home;
      fleetViewDefs = rc.views.fleet;

      # Per-host gallery: one markdown file per host embedding every
      # rendered view's SVG.
      galleryDrv =
        name: _:
        pkgs.writeText "${name}-gallery.md" ''
          # Diagram Gallery: ${name}

          Every rendered view for `${name}`. Source for each diagram is in the
          corresponding `${name}-<view>.md` file.

          ## Context Hierarchy
          ![${name} context hierarchy](./${name}-ctx.mmd.svg)

          ## Aspect Hierarchy
          ![${name} aspect hierarchy](./${name}-aspects.mmd.svg)

          ## Simplified View
          ![${name} simplified](./${name}-simple.mmd.svg)

          ## Resolution Sequence
          ![${name} resolution sequence](./${name}-seq.mmd.svg)

          ## Resolution Sequence (expanded)
          ![${name} resolution sequence expanded](./${name}-seq-full.mmd.svg)

          ## Sankey Flow
          ![${name} sankey](./${name}-sankey.mmd.svg)

          ## Treemap
          ![${name} treemap](./${name}-treemap.mmd.svg)

          ## Provider Tree
          ![${name} providers](./${name}-providers.mmd.svg)

          ## Adapter Impact
          ![${name} adapters](./${name}-adapters.mmd.svg)

          ## Structural Decisions
          ![${name} decisions](./${name}-decisions.mmd.svg)

          ## hasAspect Presence: nixos
          ![${name} hasAspect nixos](./${name}-has-aspect-nixos.mmd.svg)

          ## hasAspect Presence: homeManager
          ![${name} hasAspect homeManager](./${name}-has-aspect-hm.mmd.svg)

          ## Parametric Aspects
          ![${name} parametric](./${name}-parametric.mmd.svg)

          ## User-Declared Aspects
          ![${name} declared](./${name}-declared.mmd.svg)

          ## Class Slice: nixos
          ![${name} nixos slice](./${name}-class-nixos.mmd.svg)

          ## Class Slice: homeManager
          ![${name} hm slice](./${name}-class-hm.mmd.svg)

          ## Cross-Class Aspects
          ![${name} cross class](./${name}-cross-class.mmd.svg)

          ## Orphans and Leaves
          ![${name} orphans](./${name}-orphans.mmd.svg)

          ## Resolution Pipeline (machinery)
          ![${name} pipeline](./${name}-pipeline.mmd.svg)

          ## Provider Mindmap
          ![${name} mindmap](./${name}-mindmap.mmd.svg)

          ## Context State Diagram
          ![${name} state](./${name}-state.mmd.svg)

          ## Fan-In / Fan-Out
          ![${name} fan](./${name}-fan.mmd.svg)

          ## Class Diff (nixos vs homeManager)
          ![${name} class diff](./${name}-diff-classes.mmd.svg)

          ## C4 Container
          ![${name} C4 container](./${name}-c4container.puml.svg)

          ## C4 Component
          ![${name} C4 component](./${name}-c4component.puml.svg)

          ## Full DAG — Mermaid
          ![${name} full DAG mermaid](./${name}-dag.mmd.svg)

          ## Full DAG — Graphviz DOT
          ![${name} full DAG DOT](./${name}-dag.dot.svg)

          ## Full DAG — PlantUML
          ![${name} full DAG PlantUML](./${name}-dag.puml.svg)
        '';

      # Fleet gallery: all fleet-wide views embedded in one markdown file.
      fleetGalleryDrv = pkgs.writeText "fleet-gallery.md" ''
        # Fleet Diagram Gallery

        Flake-wide views covering every host and user in the fleet. Source for each
        diagram is in the corresponding `fleet-<view>.md` file.

        ## Aspect Namespace (declarations)
        ![Aspect namespace](./fleet-namespace.mmd.svg)

        ## C4 Context
        ![Fleet C4 Context](./fleet-c4context.puml.svg)

        ## Sankey
        ![Fleet Sankey](./fleet-sankey.mmd.svg)

        ## Treemap
        ![Fleet Treemap](./fleet-treemap.mmd.svg)

        ## Provider Matrix
        ![Fleet Provider Matrix](./fleet-provider-matrix.mmd.svg)
      '';

      # Per-host aspects source, keyed by host name, for the README gallery.
      aspectsSourcesByHost = lib.listToAttrs (
        map (host: {
          name = host.name;
          value = rc.renderDense.toMermaid (diag.graph.aspectsOnly (diag.graph.ofHost { inherit host; }));
        }) allHosts
      );

      renderedAspects = lib.concatStringsSep "\n" (
        lib.mapAttrsToList (name: source: ''
          ### ${name}

          ```mermaid
          ${source}
          ```
        '') aspectsSourcesByHost
      );

      readmeDrv = pkgs.writeText "README.md" ''
        # Diag Demo

        Aspect-resolution visualization via `den.lib.diag`: Mermaid, Graphviz DOT,
        PlantUML, and C4 diagrams rendered from structuredTrace output.

        ## Hosts

        | Host              | Adapter Pattern                              |
        | ----------------- | -------------------------------------------- |
        | `laptop`          | Baseline, no adapters, full tree             |
        | `desktop-gdm`     | Substitute regreet with gdm                  |
        | `web-server`      | Exclude nginx-exporter provider              |
        | `mail-relay`      | Exclude monitoring by aspect reference       |
        | `devbox`          | Exclude tailscale across two roles           |
        | `provider-filter` | Exclude by meta.provider prefix              |
        | `angle-brackets`  | Bracket includes + exclude adapter           |
        | `multi-desktop`   | Multi-user: alice (hyprland) + bob (gnome)   |

        ## Per-Host Views (28 per host)

        | View | Description |
        | ---- | ----------- |
        | `ctx` | Context pipeline stages as a flowchart |
        | `aspects` | Aspect hierarchy with stage subgraphs |
        | `simple` | Flat, providers folded |
        | `seq` / `seq-full` | Resolution sequence (compact / expanded) |
        | `sankey` | Flow weight by leaf count |
        | `treemap` | Provider groups |
        | `providers` | Provider hierarchy (TD tree) |
        | `adapters` | Nodes touched by adapters + neighbors |
        | `decisions` | Structural decisions (excluded vs surviving siblings) |
        | `has-aspect-nixos` | hasAspect presence slice (nixos class) |
        | `has-aspect-hm` | hasAspect presence slice (homeManager class) |
        | `parametric` | Parametric (functor) aspects + neighbors |
        | `declared` | User-declared aspects only (hasClass=true) |
        | `class-nixos` / `class-hm` | Per-class ancestor closure |
        | `cross-class` | Aspects contributing to 2+ classes |
        | `orphans` | Terminal aspects + unreachable roots |
        | `pipeline` | Resolution machinery (wrappers only) |
        | `mindmap` | Provider hierarchy as mindmap |
        | `state` | Context stages as state diagram |
        | `fan` | Fan-in/fan-out metrics sankey |
        | `diff-classes` | nixos vs homeManager overlay |
        | `ir` | Graph IR as JSON |
        | `c4container` / `c4component` | PlantUML C4 views |
        | `c4container-mmd` / `c4component-mmd` | Mermaid C4 views |
        | `dag` | Full DAG in all three formats |

        ## Fleet Views

        | View | Description |
        | ---- | ----------- |
        | `namespace` | Library declaration graph (static includes) |
        | `c4context` / `c4context-mmd` | Fleet-wide C4 context |
        | `sankey` | User-to-host provisioning flow |
        | `treemap` | Provider groups across fleet |
        | `provider-matrix` | Bipartite providers-to-hosts |

        ## User Views

        Each (host, user) pair gets its own set of views rooted at the user
        context (`den.ctx.user`). Named `<host>-<user>-<view>`.

        ```bash
        nix build .#laptop-alice-aspects      # alice's aspect tree on laptop
        nix build .#multi-desktop-bob-ctx     # bob's context pipeline
        ```

        ## Home Views

        Standalone homes (`den.homes.*`) get their own views rooted at the
        home context (`den.ctx.home`). Named `home-<name>-<view>`.

        ```bash
        nix build .#home-alice-aspects           # unbound standalone home
        nix build .#home-alice@laptop-aspects    # host-bound home
        ```

        ## Usage

        ```bash
        nix run .#write-diagrams          # writes all views + this README
        nix build .#aspects-laptop        # individual host aspect view
        nix build .#dag-laptop            # individual full DAG
        nix build .#laptop-alice-aspects  # user-rooted aspect view
        nix build .#home-alice-aspects    # home-rooted aspect view
        nix build .#fleet-namespace       # library declaration graph
        ```

        ## Rendered Traces (Aspect View)

        ${renderedAspects}
      '';

      # --- Entry generation via lib helpers ---

      inherit (diag.export)
        entityEntries
        entriesToPackages
        entriesToFiles
        entryCopyLine
        ;

      hostEntries = lib.concatMap (
        host:
        entityEntries { inherit pkgs rc diag; } {
          entity = diag.hostContext { inherit host; };
          name = host.name;
          viewDefs = hostViewDefs;
          galleryDrv = galleryDrv host.name null;
        }
      ) allHosts;

      # User entries: one set per (host, user) pair.
      allUsers = lib.concatMap (
        host:
        lib.mapAttrsToList (userName: user: {
          inherit host user;
          name = "${host.name}-${userName}";
        }) (host.users or { })
      ) allHosts;

      userEntries = lib.concatMap (
        u:
        entityEntries { inherit pkgs rc diag; } {
          entity = diag.userContext { inherit (u) host user; };
          name = u.name;
          viewDefs = userViewDefs;
        }
      ) allUsers;

      # Standalone home entries. Use the attr key (e.g. "alice@laptop")
      # as the display name, since `home.name` is just the userName
      # portion and would collide across host-bound variants.
      allHomes = lib.concatMap (
        system: lib.mapAttrsToList (key: home: { inherit home key; }) ((den.homes or { }).${system} or { })
      ) (builtins.attrNames (den.homes or { }));

      homeEntries = lib.concatMap (
        h:
        let
          safeName = lib.replaceStrings [ "@" ] [ "-at-" ] h.key;
        in
        entityEntries { inherit pkgs rc diag; } {
          entity = diag.homeContext { home = h.home; };
          name = "home-${safeName}";
          viewDefs = homeViewDefs;
        }
      ) allHomes;

      fleetEntriesList = diag.export.fleetEntries { inherit pkgs; } {
        inherit fleetData;
        viewDefs = fleetViewDefs;
        galleryDrv = fleetGalleryDrv;
      };

      everyEntry = hostEntries ++ userEntries ++ homeEntries ++ fleetEntriesList;
      allPackages = entriesToPackages everyEntry;
      allFiles = entriesToFiles everyEntry;
      writeLines = lib.concatStringsSep "\n" (map entryCopyLine everyEntry);
    in
    {
      packages = allPackages // {
        write-diagrams = pkgs.writeShellScriptBin "write-diagrams" ''
          set -euo pipefail
          dest="$(${pkgs.git}/bin/git rev-parse --show-toplevel)/templates/diag-fx-demo"
          mkdir -p "$dest/diagrams"
          # Remove stale files so deleted views/hosts don't linger.
          rm -f "$dest"/diagrams/*.md "$dest"/diagrams/*.svg
          ${writeLines}
          cat ${readmeDrv} > "$dest/README.md"
          # Remove legacy top-level GALLERY.md if present.
          rm -f "$dest/GALLERY.md"
        '';
      };

      files.gitToplevel = self;
      files.files = allFiles ++ [
        {
          path_ = "README.md";
          drv = readmeDrv;
        }
      ];
    };
}
