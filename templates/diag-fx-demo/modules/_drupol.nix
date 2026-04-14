# Import drupol/infra flake to trace their hosts.
#
# matchNot excludes:
#   - dendritic.nix         — declares drupol's `flake-file.inputs`
#                             which would conflict with our own inputs.
#                             The schema/ctx bits of that file are
#                             inlined below instead.
#   - flake-parts/*         — drupol's custom flake-parts modules
#                             (nix-unit, devshells, etc.) that don't
#                             apply to a trace-only build.
#   - systems/default.nix   — host enumeration wiring we replace
#                             with our own diag-demo setup.
#   - base/admin/nh.nix     — drupol-specific helper.
{ inputs, den, lib, ... }:
let
  import-tree = inputs.import-tree.matchNot ".*/dendritic[.]nix|.*/flake-parts/.*|.*/systems/default[.]nix|.*/base/admin/nh[.]nix";
in
{
  imports = [
    # Provides `flake-file.inputs` option used by drupol's modules.
    (inputs.flake-file.flakeModules.dendritic or { })
    (import-tree (inputs.drupol + "/modules"))
  ];

  # Reproduce the important settings from drupol/modules/dendritic.nix
  # (which we exclude via matchNot above because it also declares
  # conflicting `flake-file.inputs`). Without these the capture sees
  # no user-class content — drupol's hosts come out as bare context
  # pipeline wrappers with no actual aspects.
  den.ctx.user.includes = [ den._.mutual-provider ];
  den.schema.user.classes = lib.mkDefault [ "homeManager" ];
}
