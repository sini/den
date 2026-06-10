{
  lib,
  den,
  ...
}:
let
  # Canonical kind list from gen-schema introspection: _kindNames is sorted
  # and already excludes _-prefixed introspection keys (_topology, _edges, …).
  kindNames = den.schema._kindNames or [ ];

  # Canonical entity kind predicate: excludes the shared `conf` base and
  # non-entity schema entries (isEntity computed by gen-schema).
  schemaEntityKinds = builtins.filter (
    k: k != "conf" && (den.schema.${k}.isEntity or false)
  ) kindNames;

  # Variant for class-module.nix warnings: all schema-like arg names
  # (excludes conf, aspect) WITHOUT the isEntity check.
  # Used to detect missing den args in class module functions.
  schemaArgKinds = builtins.filter (k: k != "conf" && k != "aspect") kindNames;
  schemaEntityKindsSet = lib.genAttrs schemaEntityKinds (_: true);
in
{
  inherit schemaEntityKinds schemaEntityKindsSet schemaArgKinds;
}
