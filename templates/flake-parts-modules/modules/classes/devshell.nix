{ den, inputs, ... }:
{
  imports = [ inputs.devshell.flakeModule ];
  den.policies.flake-parts-to-flake-parts-system-devshell = {
    from = "flake-parts";
    to = "flake-parts-system";
    resolve = _: [
      {
        fromClass = _: "devshell";
        intoPath = _: [
          "devshells"
          "default"
        ];
      }
    ];
  };
}
