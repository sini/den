{ den, lib, inputs, ... }:
let
  fx = inputs.nix-effects.lib;
  fxLib = den.lib.aspects.fx.init fx;
  allHosts = lib.concatMap builtins.attrValues (builtins.attrValues den.hosts);
  hostByName = name: lib.findFirst (h: h.name == name) (builtins.head allHosts) allHosts;
  targetHost = hostByName "angle-brackets";
  legacyRoot = den.ctx.host { host = targetHost; };
  nxFx = inputs.nix-effects.lib;

  # FX resolve with tracing
  comp = nxFx.bind
    (fxLib.resolve.resolveDeepEffectful { ctx = {}; class = "nixos"; aspect-chain = []; } legacyRoot)
    (resolved: nxFx.bind (nxFx.send "resolve-complete" (resolved // { __parent = null; })) (_: nxFx.pure resolved));
  result = nxFx.handle {
    handlers = fxLib.resolve.defaultHandlers { class = "nixos"; ctx = {}; }
      // fxLib.adapters.tracingHandler "nixos"
      // fxLib.handlers.ctxTraceHandler;
    state = fxLib.resolve.defaultState // { entries = []; paths = []; ctxTrace = []; };
  } comp;
  entries = result.state.entries;

  # Find tailscale entries
  tailscaleEntries = builtins.filter (e:
    e.name == "tailscale" || e.name == "~tailscale"
  ) entries;
in
{
  flake.debug = {
    hostName = targetHost.name;
    entryCount = builtins.length entries;
    tailscaleEntries = map (e: {
      name = e.name;
      excluded = e.excluded or false;
      parent = e.parent or null;
      ctxStage = e.ctxStage or null;
    }) tailscaleEntries;
    registryKeys = builtins.attrNames (result.state.adapterRegistry or {});
  };
}
