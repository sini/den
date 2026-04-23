# A policy declares a directed edge between entity kinds with a
# resolve function that performs fan-out/discrimination.
{ lib, ... }:
let
  policyType = lib.types.submodule {
    options = {
      from = lib.mkOption {
        type = lib.types.str;
        description = "Source entity kind (e.g., 'host')";
      };
      to = lib.mkOption {
        type = lib.types.str;
        description = "Target entity kind or stage name (e.g., 'user', 'hm-host')";
      };
      resolve = lib.mkOption {
        type = lib.types.raw;
        description = ''
          Function that takes accumulated pipeline context and returns
          a list of target context attrsets.
          Example: { host }: map (user: { inherit host user; }) (lib.attrValues host.users)
        '';
      };
    };
  };
in
{
  inherit policyType;
}
