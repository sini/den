# Fleet topology and user-access policies.
#
# Wires the scope tree: flake -> fleet -> environment -> hosts -> users.
# Each environment groups its hosts as siblings for pipe.collect.
#
# Environment membership derived from den.schema.host.environment.
# Environment entities read from fleet.environments registry.
# User resolution driven by fleet.user-access group intersection.
{
  lib,
  den,
  config,
  ...
}:
let
  inherit (den.lib.policy) resolve;

  # Filter registry user names whose groups intersect the granted set.
  matchRegistryUsers =
    grantedGroups: registry:
    lib.filter (name: builtins.any (g: lib.elem g grantedGroups) registry.${name}.groups) (
      builtins.attrNames registry
    );
in
{
  # flake -> fleet: single fleet entity.
  den.policies.to-fleet = _: [
    (resolve.to "fleet" {
      fleet = {
        name = "fleet";
      };
    })
  ];

  # fleet -> environments: fan out per registered environment.
  den.policies.fleet-to-envs =
    { fleet, ... }:
    lib.mapAttrsToList (
      _: env:
      resolve.to "environment" {
        environment = env;
      }
    ) config.fleet.environments;

  # environment -> hosts: walk hosts whose environment matches.
  # Guard: only fire at environment scope (not at host scopes which inherit environment).
  den.policies.env-to-hosts =
    { environment, ... }:
    lib.concatMap (
      system:
      lib.concatMap (
        hostName:
        let
          hostCfg = den.hosts.${system}.${hostName};
        in
        lib.optionals ((hostCfg.environment or "default") == environment.name && hostCfg.intoAttr != [ ]) [
          (resolve.to "host" { host = hostCfg; })
          (den.lib.policy.instantiate hostCfg)
        ]
      ) (builtins.attrNames (den.hosts.${system} or { }))
    ) (builtins.attrNames (den.hosts or { }));

  # host -> users (by environment): resolve registry users whose groups match.
  den.policies.env-users =
    { host, config, ... }:
    let
      grant = config.fleet.user-access.by-environment.${host.environment} or { groups = [ ]; };
      matched = matchRegistryUsers grant.groups config.den.users.registry;
    in
    map (name: resolve.to "user" { user = config.den.users.registry.${name}; }) matched;

  # host -> users (by host): resolve registry users by host-specific group match.
  den.policies.host-users =
    { host, config, ... }:
    let
      grant = config.fleet.user-access.by-host.${host.name} or { groups = [ ]; };
      matched = matchRegistryUsers grant.groups config.den.users.registry;
    in
    map (name: resolve.to "user" { user = config.den.users.registry.${name}; }) matched;

  den.schema.flake.includes = [ den.policies.to-fleet ];
  den.schema.fleet.includes = [ den.policies.fleet-to-envs ];
  den.schema.environment.includes = [ den.policies.env-to-hosts ];
  den.schema.host.includes = [
    den.policies.env-users
    den.policies.host-users
  ];
  den.schema.host.excludes = [ den.policies.host-to-users ];
}
