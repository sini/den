{
  inputs,
  lib,
  config,
  ...
}:
let
  inherit (config) den;
  types = import ./../nix/lib/types.nix {
    inherit
      inputs
      lib
      den
      config
      ;
  };
  schemaLib = inputs.gen-schema.lib;

  classSchemaType = lib.types.submodule (
    { ... }:
    {
      options.description = lib.mkOption {
        description = "Human-readable description of this class domain.";
        type = lib.types.str;
      };
      options.forwardTo = lib.mkOption {
        description = "Optional forward target for class evaluation.";
        type = lib.types.nullOr lib.types.raw;
        default = null;
      };
    }
  );

  pipeSchemaType = lib.types.submodule (
    { ... }:
    {
      options.description = lib.mkOption {
        description = "Human-readable description of this pipe.";
        type = lib.types.str;
      };
    }
  );
in
{
  options.den.hosts = types.hostsOption;
  options.den.homes = types.homesOption;
  options.den.schema = schemaLib.mkSchemaOption {
    sidecars = {
      includes = {
        default = [ ];
      };
      excludes = {
        default = [ ];
      };
      isEntity = {
        default = false;
        merge = acc: val: acc || val;
      };
    };
    computed = _kind: sidecars: defs: {
      isEntity =
        sidecars.isEntity
        || builtins.any (
          d:
          let
            v = d.value;
            sidecarKeys = [
              "includes"
              "excludes"
              "isEntity"
              "collisionPolicy"
            ];
            stripped = if builtins.isAttrs v then builtins.removeAttrs v sidecarKeys else v;
          in
          !builtins.isAttrs stripped || stripped != { }
        ) defs;
    };
  };
  options.den.classes = lib.mkOption {
    description = "Class evaluation domains";
    type = lib.types.lazyAttrsOf classSchemaType;
    default = { };
  };
  options.den.quirks = lib.mkOption {
    description = "Quirk declarations — named data routes for structured quirk flow";
    type = lib.types.lazyAttrsOf pipeSchemaType;
    default = { };
    apply =
      quirks:
      let
        classKeys = builtins.attrNames (den.classes or { });
        overlap = builtins.filter (k: builtins.elem k classKeys) (builtins.attrNames quirks);
      in
      assert
        overlap == [ ]
        || throw "den.classes and den.quirks must not share keys, but found: ${builtins.concatStringsSep ", " overlap}";
      lib.mapAttrs (name: v: v // { inherit name; }) quirks;
  };
  config.den.schema = {
    conf = { };
    fleet = { };
    host.imports = [ den.schema.conf ];
    user.imports = [ den.schema.conf ];
    home.imports = [ den.schema.conf ];
    _topology.host.children = [ "user" ];
  };
  config.den.classes = {
    nixos.description = "NixOS system configuration";
    darwin.description = "nix-darwin system configuration";
  };
}
