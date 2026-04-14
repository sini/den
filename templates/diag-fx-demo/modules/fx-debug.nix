{ den, lib, inputs, ... }:
let
  fx = inputs.nix-effects.lib;
  fxLib = den.lib.aspects.fx.init fx;
  allHosts = lib.concatMap builtins.attrValues (builtins.attrValues den.hosts);
  hostByName = name: lib.findFirst (h: h.name == name) (builtins.head allHosts) allHosts;
  targetHost = hostByName "desktop-gdm";
  legacyResolve = den.lib.aspects.legacyResolve;
  legacyRoot = den.ctx.host { host = targetHost; };
  nxFx = inputs.nix-effects.lib;
  fxComp = nxFx.bind
    (fxLib.resolve.resolveDeepEffectful { ctx = {}; class = "nixos"; aspect-chain = []; } legacyRoot)
    (resolved: nxFx.bind (nxFx.send "resolve-complete" (resolved // { __parent = null; })) (_: nxFx.pure resolved));
  fxResult = nxFx.handle {
    handlers = fxLib.resolve.defaultHandlers "nixos"
      // fxLib.adapters.tracingHandler "nixos"
      // fxLib.handlers.ctxTraceHandler;
    state = fxLib.resolve.defaultState // { entries = []; paths = []; ctxTrace = []; };
  } fxComp;
  fxEntries = fxResult.state.entries;
  legacyResult = legacyResolve.withAdapter den.lib.aspects.adapters.structuredTrace "nixos" legacyRoot;
  legacyEntries = legacyResult.trace or [];
  meaningful = n: n != "<anon>" && n != "<function body>" && !(lib.hasPrefix "[definition " n);
  sort = lib.sort (a: b: a < b);
  unique = lib.unique;
  fxUniqueNames = sort (unique (map (e: e.name) fxEntries));
  legacyUniqueNames = sort (unique (map (e: e.name) legacyEntries));
  inLegacyNotFx = builtins.filter (n: !(builtins.elem n fxUniqueNames)) legacyUniqueNames;
  inFxNotLegacy = builtins.filter (n: !(builtins.elem n legacyUniqueNames)) fxUniqueNames;
in
{
  flake.debug = {
    hostName = targetHost.name;
    fxEntryCount = builtins.length fxEntries;
    legacyEntryCount = builtins.length legacyEntries;
    fxAnonCount = builtins.length (builtins.filter (e: !meaningful e.name) fxEntries);
    fxUniqueCount = builtins.length fxUniqueNames;
    legacyUniqueCount = builtins.length legacyUniqueNames;
    inLegacyNotFx = inLegacyNotFx;
    inFxNotLegacy = inFxNotLegacy;
  };
}
