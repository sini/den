{ den, lib, inputs, ... }:
let
  fx = inputs.nix-effects.lib;
  fxLib = den.lib.aspects.fx.init fx;
  allHosts = lib.concatMap builtins.attrValues (builtins.attrValues den.hosts);
  hostByName = name: lib.findFirst (h: h.name == name) (builtins.head allHosts) allHosts;
  targetHost = hostByName "angle-brackets";
  legacyResolve = den.lib.aspects.legacyResolve;
  legacyRoot = den.ctx.host { host = targetHost; };
  nxFx = inputs.nix-effects.lib;

  # FX trace
  fxComp = nxFx.bind
    (fxLib.resolve.resolveDeepEffectful { ctx = {}; class = "nixos"; aspect-chain = []; } legacyRoot)
    (resolved: nxFx.bind (nxFx.send "resolve-complete" resolved) (_: nxFx.pure resolved));
  fxResult = nxFx.handle {
    handlers = fxLib.resolve.defaultHandlers { class = "nixos"; ctx = {}; }
      // fxLib.trace.tracingHandler "nixos"
      // fxLib.handlers.ctxTraceHandler;
    state = fxLib.resolve.defaultState // { entries = []; paths = []; ctxTrace = []; };
  } fxComp;

  # Legacy trace
  legacyResult = legacyResolve.withAdapter den.lib.aspects.adapters.structuredTrace "nixos" legacyRoot;

  # Compare parent assignments for specific aspects
  fxEntries = fxResult.state.entries;
  legacyEntries = legacyResult.trace or [];

  getParents = name: entries:
    map (e: e.parent or "NULL")
      (builtins.filter (e: e.name == name) entries);

  # Also check raw entries from resolve-complete params
  fxRawParents = lib.genAttrs aspects (name:
    let matches = builtins.filter (e: e.name == name) fxEntries; in
    map (e: { parent = e.parent or "NULL"; ctxStage = e.ctxStage or "?"; }) matches
  );

  aspects = [ "hyprland" "dev-tools" "desktop" "networking" "regreet" "alice" "primary-user" ];
in
{
  flake.debug = {
    fxEdgeCount = builtins.length (builtins.filter (e: e.parent or null != null) fxEntries);
    legacyEdgeCount = builtins.length (builtins.filter (e: e.parent or null != null) legacyEntries);
    fxRawParents = fxRawParents;
    parentComparison = lib.genAttrs aspects (name: {
      fx = getParents name fxEntries;
      legacy = getParents name legacyEntries;
    });
  };
}
