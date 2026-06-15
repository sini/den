{ lib }:
let
  inherit (import ./edge.nix { inherit lib; }) edgeSortKey;
in
{
  # assertEdgeParity — the cross-pipeline parity diff. Diffs two delivery-edge
  # traces by normalized identity key (T,P,S,M; annotations EXCLUDED — the parity
  # contract is STRUCTURAL, spec §4). Returns matched + the asymmetric differences
  # + a boolean. The §5.1 deviation classification (bug-in-hoag | bug-in-v1 |
  # intentional-v2) is a HUMAN step over this diff (parity/edge-schema.md runbook),
  # not automated here.
  assertEdgeParity =
    { expected, actual }:
    let
      keyOf = edgeSortKey;
      expKeys = lib.genAttrs (map keyOf expected) (_: true);
      actKeys = lib.genAttrs (map keyOf actual) (_: true);
    in
    rec {
      matched = lib.filter (e: actKeys ? ${keyOf e}) expected;
      missingFromActual = lib.filter (e: !(actKeys ? ${keyOf e})) expected;
      extraInActual = lib.filter (e: !(expKeys ? ${keyOf e})) actual;
      parity = missingFromActual == [ ] && extraInActual == [ ];
    };
}
