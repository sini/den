{
  den,
  lib,
  options,
  inputs,
  ...
}:
let
  has-flake-output =
    output: ((options.flake.type.getSubOptions or (_: options.flake)) { }) ? ${output};

  systemOutputFwd =
    { system, output }:
    { class, aspect-chain }:
    den.provides.forward {
      each = lib.optional (class == "flake") output;
      fromClass = _: output;
      intoClass = _: "flake";
      intoPath = _: [
        "flake"
        output
        system
      ];
      guard = _: has-flake-output output;
      adaptArgs = _: { pkgs = inputs.nixpkgs.legacyPackages.${system}; };
      fromAspect = _: lib.head aspect-chain;
    };

  outputs = [
    "packages"
    "apps"
    "checks"
    "devShells"
    "legacyPackages"
  ];

  stageSystemOuts = map (output: {
    flake-system.provides."flake-${output}" = _: systemOutputFwd;
  }) outputs;

in
{
  den.stages = lib.mkMerge stageSystemOuts;
}
