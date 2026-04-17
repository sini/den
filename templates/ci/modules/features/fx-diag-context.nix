# Tests for the diag library's context graph construction via fx pipeline.
# Reproduces the path that diag-fx-demo templates use: build a host,
# resolve via den.ctx.host, capture traces, construct graph IR.
{
  denTest,
  inputs,
  lib,
  ...
}:
let
  fx = inputs.nix-effects.lib;
in
{
  flake.tests.fx-diag-context = {

    # Build a hostContext graph from a minimal host with fx pipeline.
    test-host-context-fx = denTest (
      { den, ... }:
      {
        den.fxPipeline = true;
        den.hosts.x86_64-linux.testhost.users.tux = { };
        den.aspects.testhost.nixos =
          { ... }:
          {
            networking.hostName = "fx-diag-test";
          };
        expr =
          let
            host = lib.head (builtins.attrValues den.hosts.x86_64-linux);
            graph = den.lib.diag.hostContext { inherit host; };
          in
          {
            hasNodes = (graph.nodes or [ ]) != [ ];
            hasEdges = graph ? edges;
            rootName = graph.rootName or "unknown";
          };
        expected = {
          hasNodes = true;
          hasEdges = true;
          rootName = "testhost";
        };
      }
    );

    # Capture fx trace entries directly.
    test-fx-capture-in-context = denTest (
      { den, ... }:
      {
        den.fxPipeline = true;
        den.hosts.x86_64-linux.testhost.users.tux = { };
        den.aspects.testhost.nixos =
          { ... }:
          {
            networking.hostName = "test";
          };
        den.aspects.testhost.includes = [
          den.aspects.networking
        ];
        den.aspects.networking.nixos =
          { ... }:
          {
            networking.firewall.enable = true;
          };
        expr =
          let
            host = lib.head (builtins.attrValues den.hosts.x86_64-linux);
            root = den.ctx.host { inherit host; };
            fxLib = den.lib.aspects.fx;
            result = den.lib.diag.fxCaptureWithPaths fxLib [ "nixos" ] root;
          in
          {
            hasEntries = (builtins.length result.entries) > 0;
            hasPathsByClass = result.pathsByClass ? nixos;
          };
        expected = {
          hasEntries = true;
          hasPathsByClass = true;
        };
      }
    );

    # Reproduce template pattern: aspect uses den.lib.aspects.fx.exclude
    # in meta.handleWith — same as diag-fx-demo/aspects/hosts/angle-brackets.nix
    test-handleWith-exclude-in-aspect = denTest (
      { den, ... }:
      {
        den.fxPipeline = true;
        den.hosts.x86_64-linux.testhost.users.tux = { };
        den.aspects.testhost = {
          includes = [
            den.aspects.networking
            den.aspects.desktop
          ];
          meta.handleWith = den.lib.aspects.fx.constraints.exclude den.aspects.tailscale;
        };
        den.aspects.networking.nixos =
          { ... }:
          {
            networking.firewall.enable = true;
          };
        den.aspects.desktop.nixos =
          { ... }:
          {
            services.xserver.enable = true;
          };
        den.aspects.tailscale.nixos =
          { ... }:
          {
            services.tailscale.enable = true;
          };
        expr =
          let
            host = lib.head (builtins.attrValues den.hosts.x86_64-linux);
            graph = den.lib.diag.hostContext { inherit host; };
          in
          {
            hasNodes = (graph.nodes or [ ]) != [ ];
          };
        expected = {
          hasNodes = true;
        };
      }
    );

    # Test with den.lib.aspects.fx.constraints accessed in aspect definition
    test-fx-constraints-access = denTest (
      { den, ... }:
      let
        excludeDecl = den.lib.aspects.fx.constraints.exclude {
          name = "drop";
          meta.provider = [ ];
        };
      in
      {
        expr = excludeDecl.type;
        expected = "exclude";
      }
    );

  };
}
