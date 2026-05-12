# Potential issues identified by debugging agents during skill evaluation.
{
  denTest,
  inputs,
  lib,
  ...
}:
{
  flake.tests.deadbugs.agent-findings = {

    # Finding 1: mergeContentValuesPerKey edge case.
    # When one file provides a NixOS module function and the other an attrset,
    # the function is excluded from attrVals, causing fallback to
    # unwrapContentValuesRaw which produces { imports = vals; }.
    test-function-and-attrset-mixed-content = denTest (
      { den, igloo, ... }:
      {
        imports = [
          # Module A: function value for nixos
          {
            den.aspects.igloo.base.nixos =
              { config, ... }:
              {
                environment.variables.FROM_FN = "yes";
              };
          }
          # Module B: attrset value for nixos
          {
            den.aspects.igloo.base.nixos.environment.variables.FROM_ATTR = "yes";
          }
        ];

        den.hosts.x86_64-linux.igloo.users.tux = { };

        expr = {
          hasFn = igloo.environment.variables ? FROM_FN;
          hasAttr = igloo.environment.variables ? FROM_ATTR;
        };
        expected = {
          hasFn = true;
          hasAttr = true;
        };
      }
    );

    # Finding 2: namespace provider content wrapper + nested keys.
    # Including a namespace freeform child that has nested sub-aspects
    # should still auto-walk those nested keys (they aren't independently
    # defined sub-aspects, they're organizational nesting within a single
    # namespace aspect definition).
    test-namespace-nested-auto-walk = denTest (
      { den, igloo, inputs, ... }:
      {
        imports = [ (inputs.den.namespace "ns" [ ]) ];

        den.hosts.x86_64-linux.igloo.users.tux = { };

        ns.tools.monitoring = {
          nixos.environment.variables.MONITORING = "yes";
        };

        den.aspects.igloo.includes = [ ns.tools.monitoring ];

        expr = {
          hasMonitoring = igloo.environment.variables ? MONITORING;
        };
        expected = {
          hasMonitoring = true;
        };
      }
    );

    # Finding 2b: namespace provider with parametric fn at nested key.
    test-namespace-parametric-child = denTest (
      { den, igloo, inputs, ... }:
      {
        imports = [ (inputs.den.namespace "ns" [ ]) ];

        den.hosts.x86_64-linux.igloo.users.tux = { };

        ns.tools.monitoring =
          { host, ... }:
          {
            nixos.networking.hostName = "${host.name}-monitored";
          };

        den.aspects.igloo.includes = [ ns.tools.monitoring ];

        expr = igloo.networking.hostName;
        expected = "igloo-monitored";
      }
    );

  };
}
