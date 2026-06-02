name: sources:
{ config, lib, ... }:
let
  from = lib.flatten [ sources ];
  isOutput = builtins.elem true from;
  denfuls = map (lib.getAttrFromPath [
    "denful"
    name
  ]) (builtins.filter builtins.isAttrs from);

  # Strip _ aliases from external denful to prevent duplication on re-import.
  # The _ → provides alias in aspectSubmodule means evaluated configs contain
  # both _ and provides with identical content. Re-importing both causes
  # listOf options (like includes) to merge duplicates.
  # The root `_` is the synthetic namespace provides bundle (a computed,
  # read-only option). Like the aspect-level `_` aliases inside each value, it
  # must not round-trip as a definition — drop it before re-feeding so the
  # importing side recomputes its own bundle instead of colliding with it.
  stripAliases =
    denful:
    lib.mapAttrs (
      _: v:
      if builtins.isAttrs v then
        builtins.removeAttrs v [
          "_"
          "__functor"
        ]
      else
        v
    ) (builtins.removeAttrs denful [ "_" ]);
  sourceModules = map (denful: { config.den.ful.${name} = stripAliases denful; }) denfuls;

  aliasModule = lib.mkAliasOptionModule [ name ] [ "den" "ful" name ];

  outputModule = lib.optionalAttrs isOutput {
    # Don't serialize the computed `_` bundle into the exported namespace; it's
    # recomputed on import (and would otherwise collide with the read-only
    # option — see stripAliases).
    config.flake.denful.${name} = builtins.removeAttrs config.den.ful.${name} [ "_" ];
  };

  # Merge external source classes into den.classes.
  # Local namespace classes are collected by aspect-schema.nix.
  traitClassModule = {
    config.den.classes = lib.mkMerge (map (denful: denful.classes or { }) denfuls);
  };
in
{
  imports = sourceModules ++ [
    aliasModule
    outputModule
    traitClassModule
  ];
  config._module.args.${name} = config.den.ful.${name};
}
