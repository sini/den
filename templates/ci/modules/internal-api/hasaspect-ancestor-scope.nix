# Regression: projected (in-context) hasAspect under an ANCESTOR entity-kind
# scope.
#
# A host resolved under a fleet-style topology (flake → tier → host, where
# `tier` is an entity kind like an environment) inherits the `tier` binding in
# its production ctx. The projected hasAspect must still resolve against the
# owning host's bucket — which is produced by the host's OWN standalone run and
# knows nothing of the ancestor `tier`. Buckets are keyed by entity identity
# (`id_hash`), which is context-free (kind+name, not ancestry), so the consuming
# host looks itself up by its own id_hash regardless of any ancestor scopes —
# no scope-string reconstruction, no ancestor to strip. The historical bug
# (keying by a reconstructed "tier=prod,host=igloo" scope-string vs a bucket
# keyed "host=igloo") read false here and dropped agenix's /persist prefix
# (identityPaths → /etc/ssh). den's default flake→system→host walk hides it
# because `system` is a plain string, not an entity kind.
{ denTest, lib, ... }:
{
  flake.tests.hasaspect-ancestor-scope = {

    test-projected-hasaspect-under-ancestor-tier = denTest (
      { den, igloo, ... }:
      let
        inherit (den.lib.policy) resolve instantiate;
      in
      {
        # Insert an entity-kind `tier` between flake-system and host:
        # flake-system → tier → host. host.parent = tier makes tier an ANCESTOR.
        den.schema.tier.isEntity = true;
        den.schema.host.parent = "tier";
        den.schema.flake-system.excludes = [ den.policies.system-to-os-outputs ];
        den.policies.test-tier-walk = { system, ... }: [ (resolve.to "tier" { tier.name = "prod"; }) ];
        den.policies.test-tier-to-host =
          { system, ... }:
          lib.concatMap (
            host:
            lib.optionals (host.intoAttr != [ ]) [
              (resolve.to "host" { inherit host; })
              (instantiate host)
            ]
          ) (builtins.attrValues (den.hosts.${system} or { }));
        den.schema.flake-system.includes = [ den.policies.test-tier-walk ];
        den.schema.tier.includes = [ den.policies.test-tier-to-host ];

        den.hosts.x86_64-linux.igloo.users.tux = { };
        # transitively-included, settings-bearing, namespaced aspect (the
        # core.impermanence shape).
        den.aspects.svc.feature = {
          settings.opt = lib.mkOption {
            type = lib.types.bool;
            default = true;
          };
          nixos = { };
        };
        den.aspects.role.includes = [ den.aspects.svc.feature ];
        den.aspects.igloo.includes = [ den.aspects.role ];
        den.hosts.x86_64-linux.igloo.settings.svc.feature.opt = true;

        # agenix-shape host-include that reads the PROJECTED host.hasAspect.
        den.schema.host.includes = [
          (
            { host, ... }:
            {
              nixos.environment.etc."has-feature".text = lib.boolToString (
                host.hasAspect den.aspects.svc.feature
              );
            }
          )
        ];

        expr = igloo.environment.etc."has-feature".text;
        expected = "true";
      }
    );
  };
}
