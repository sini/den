# Renders aspect resolution traces as Mermaid graphs.
#   nix run .#write-files    - writes traces/ and README.md
#   nix build .#trace-laptop - individual trace
{
  den,
  lib,
  inputs,
  ...
}:
let
  allHosts = lib.concatMap builtins.attrValues (builtins.attrValues den.hosts);

  isMeaningful =
    name: name != "<anon>" && name != "<function body>" && !(lib.hasPrefix "[definition " name);

  traceToMermaid =
    hostName: trace:
    let
      meaningful = builtins.filter (t: isMeaningful t.name) trace;
      sanitize = name: lib.replaceStrings [ "-" " " "." "@" "/" ] [ "_" "_" "_" "_" "_" ] name;

      # Show provider origin as qualified label
      displayName =
        entry:
        if entry ? provider && entry.provider != [ ] then
          lib.concatStringsSep "/" (entry.provider ++ [ entry.name ])
        else
          entry.name;

      findParent =
        chain:
        let
          m = builtins.filter isMeaningful chain;
        in
        if m == [ ] then hostName else lib.last m;

      # Group entries by class
      classes = lib.unique (map (t: t.class or "nixos") meaningful);
      hasMultipleClasses = builtins.length classes > 1;

      # Deduplicate nodes by display name (qualified path), preferring provider-tagged entries
      dedup =
        let
          step =
            acc: entry:
            let
              key = displayName entry;
              dominated = acc.seen ? ${key} && !(entry ? provider);
              upgrade = acc.seen ? ${key} && entry ? provider && !(acc.seen.${key} ? provider);
            in
            if dominated then
              acc
            else if upgrade then
              {
                seen = acc.seen // {
                  ${key} = entry;
                };
                result = map (e: if displayName e == key then entry else e) acc.result;
              }
            else if acc.seen ? ${key} then
              acc
            else
              {
                seen = acc.seen // {
                  ${key} = entry;
                };
                result = acc.result ++ [ entry ];
              };
        in
        (builtins.foldl' step {
          seen = { };
          result = [ ];
        } meaningful).result;

      # Build edges from all entries (not deduped, to capture cross-class edges)
      edges = builtins.concatMap (
        entry:
        if entry.name == hostName then
          [ ]
        else
          [
            (
              {
                from = findParent entry.chain;
                to = entry.name;
                decision = entry.decision;
                class = entry.class or "nixos";
              }
              // lib.optionalAttrs (entry ? replacedBy) { inherit (entry) replacedBy; }
            )
          ]
      ) meaningful;

      dedupEdges =
        let
          step =
            acc: edge:
            let
              k = "${edge.from}-->${edge.to}:${edge.class}";
              dominated = acc.seen ? ${k} && edge.decision != "pruned";
              upgrade = acc.seen ? ${k} && edge.decision == "pruned" && acc.seen.${k}.decision != "pruned";
            in
            if edge.from == edge.to then
              acc
            else if dominated then
              acc
            else if upgrade then
              {
                seen = acc.seen // {
                  ${k} = edge;
                };
                result = map (
                  e:
                  let
                    ek = "${e.from}-->${e.to}:${e.class}";
                  in
                  if ek == k then edge else e
                ) acc.result;
              }
            else if acc.seen ? ${k} then
              acc
            else
              {
                seen = acc.seen // {
                  ${k} = edge;
                };
                result = acc.result ++ [ edge ];
              };
        in
        (builtins.foldl' step {
          seen = { };
          result = [ ];
        } edges).result;

      nodeDecl =
        entry:
        let
          id = sanitize entry.name;
          label = displayName entry;
          style =
            if entry.decision == "pruned" then
              ":::excluded"
            else if entry.decision == "replaced" then
              ":::replaced"
            else
              "";
          replacementNode =
            if entry.decision == "replaced" && entry ? replacedBy then
              "\n  ${sanitize entry.replacedBy}[${entry.replacedBy}]"
            else
              "";
        in
        "  ${id}[${label}]${style}${replacementNode}";

      edgeDecl =
        edge:
        let
          fromId = sanitize edge.from;
          toId = sanitize edge.to;
          arrow =
            if edge.decision == "pruned" then
              "-.-x"
            else if edge.decision == "replaced" then
              "-.->|replaced|"
            else
              "-->";
          replacementEdge = if edge ? replacedBy then "\n  ${fromId} --> ${sanitize edge.replacedBy}" else "";
        in
        "  ${fromId} ${arrow} ${toId}${replacementEdge}";

      edgesForClass = cls: builtins.filter (e: e.class == cls) dedupEdges;

      classSubgraph =
        cls:
        let
          clsEdges = edgesForClass cls;
        in
        if clsEdges == [ ] then
          [ ]
        else
          [ "  subgraph ${sanitize cls}[${cls}]" ] ++ (map edgeDecl clsEdges) ++ [ "  end" ];

      # Single-class: flat graph. Multi-class: subgraphs.
      edgeSection =
        if hasMultipleClasses then lib.concatMap classSubgraph classes else map edgeDecl dedupEdges;

    in
    lib.concatStringsSep "\n" (
      [ "graph TD" ]
      ++ [ "  ${sanitize hostName}([${hostName}]):::host" ]
      ++ (map nodeDecl (builtins.filter (e: e.name != hostName) dedup))
      ++ [ "" ]
      ++ edgeSection
      ++ [
        ""
        "  classDef host fill:#4a9,stroke:#2d7,color:#fff,font-weight:bold"
        "  classDef excluded fill:#f99,stroke:#f00,stroke-dasharray: 5 5"
        "  classDef replaced fill:#ff9,stroke:#fa0"
      ]
    );

  traceHost =
    host:
    let
      asp = den.ctx.host { inherit host; };
      result = den.lib.aspects.resolve' host.class { trace = true; } asp;
    in
    {
      name = host.name;
      value = traceToMermaid host.name result.trace;
    };

  allTraces = builtins.listToAttrs (map traceHost allHosts);

  traceSection =
    name: mermaid:
    let
      title = lib.replaceStrings [ "-substitute-" ] [ " with substitute transformer: " ] name;
    in
    ''
      ### ${title}

      ```mermaid
      ${mermaid}
      ```
    '';

  renderedTraces = lib.concatStringsSep "\n" (lib.mapAttrsToList traceSection allTraces);

in
{
  flake.packages.x86_64-linux =
    let
      pkgs = inputs.nixpkgs.legacyPackages.x86_64-linux;
    in
    lib.mapAttrs' (
      name: mermaid:
      lib.nameValuePair "trace-${name}" (
        pkgs.writeText "trace-${name}.md" ''
          # Aspect Hierarchy: ${name}

          ```mermaid
          ${mermaid}
          ```
        ''
      )
    ) allTraces;

  # Paths relative to git root since den.url = "path:../..".
  perSystem =
    { pkgs, config, ... }:
    {
      files.files =
        (lib.mapAttrsToList (name: mermaid: {
          path_ = "./templates/transform-trace-demo/traces/trace-${name}.md";
          drv = pkgs.writeText "trace-${name}.md" ''
            # Aspect Hierarchy: ${name}

            ```mermaid
            ${mermaid}
            ```
          '';
        }) allTraces)
        ++ [
          {
            path_ = "./templates/transform-trace-demo/README.md";
            drv = pkgs.writeText "README.md" ''
              # Showcase: Aspect Transforms, Excludes, and Trace

              Demonstrates den's aspect transform system: entity-level excludes,
              the `substitute` transformer, and resolution tracing with Mermaid visualization.

              ## Hosts

              | Host          | Role        | Notes                                                              |
              | ------------- | ----------- | ------------------------------------------------------------------ |
              | `laptop`      | Workstation | Desktop with regreet greeter and tailscale                         |
              | `desktop-gdm` | Workstation | Same as laptop; use the substitute transformer to swap the greeter |
              | `web-server`  | Server      | Headless with monitoring and tailscale                             |
              | `mail-relay`  | Relay       | Server role with monitoring excluded at the host level             |

              ## Usage

              ```bash
              nix run .#write-files     # writes traces/ and this README
              nix build .#trace-laptop  # individual trace derivation
              ```

              ## Rendered Traces

              Generated by `nix run .#write-files`.

              ${renderedTraces}
              ## Notes

              Excludes can be declared on host entities (`den.hosts.*.excludes`)
              or on aspects (`den.aspects.*.excludes`). Both propagate into
              nested includes. See `devbox` for an example of aspect-level
              excludes removing `tailscale` from both `workstation` and `server`.

              To swap a nested aspect (like a greeter), use the `substitute`
              transformer via `resolve'`. See `desktop-gdm` for an example.
            '';
          }
        ];

      packages.write-files = config.files.writer.drv;
    };
}
