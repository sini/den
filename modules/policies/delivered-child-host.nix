# Delivered child host — a reusable primitive for nesting a *guest* host
# inside a *parent* host's instantiated configuration (e.g. a microvm guest
# realized into parent.microvm.vms.<name>.config) instead of producing a
# standalone nixosConfigurations.<name> output.
#
# ===================== DESIGN (entity-isolation) ===========================
#
# DELIVERY = entity-isolation + a collect/append-decoupled route. The guest
# authors honest `nixos` content; a dedicated `delivered-guest` kind marked
# `isolated = true` keeps that content out of the parent's own toplevel nixos
# partition (isolation-aware subtree extraction skips isolated descendants and
# everything below them — see spec
# 2026-06-11-entity-isolation-aware-extraction-design.md).
#
# Two EXISTING mechanisms composed, NO further den-core change here:
#
#   1. resolve.to.withIncludes "<guest-kind>" [ deliverPolicy ]
#        { delivered-guest = guest; host = guest; }
#      nests the guest as an isolated child entity scope under the parent host.
#      The `host` binding rebinds host to the guest INSIDE the guest scope so
#      curated host-include policies (host-to-users, the standard home-manager
#      battery, den.default) fire for the guest as if it were a host. The
#      `delivered-guest` binding makes resolveEntityClass derive the guest's
#      class (always nixos here).
#
#   2. The delivery route is registered INSIDE the guest scope (a resolve
#      include). It collects `fromClass = "nixos"` rooted at the guest scope
#      (the collection root is exempt from isolation) and, via
#      `appendToParent = true`, lands the wrapped result at the PARENT scope
#      under the delivery path. The guest carries intoAttr = [] and gets NO
#      policy.instantiate, so it produces NO standalone flake output.
#
#   (redirect-instantiate — writing into flake.nixosConfigurations.<p>.config.*
#   — is a DEAD END: nixosConfigurations is lazyAttrsOf raw, an already-
#   evaluated nixosSystem; writing its .config subpath collides with the
#   read-only result instead of injecting a module.)
#
# KIND = a DEDICATED `delivered-guest` kind whose `includes` are a CURATED
# subset of `den.schema.host.includes`, DERIVED (not hand-copied) so it tracks
# host.includes:
#   INHERIT  participation/identity/collect includes (host-to-users, the
#            standard home-manager battery, den.default).
#   OMIT     includes producing a standalone instantiate output (nix-config's
#            colmena host-modules-capture) — a child must not instantiate. Named
#            via `den.deliveredChild.omitIncludeNames`. No-op in den-only tests
#            (colmena is a nix-config host-include, not a den one).
#   RETARGET / OVERRIDE  agenix-style host-includes whose class lookup or key
#            paths assume the host class: the consumer points public_key /
#            secret sources at the parent and targets nixos. Expressed as
#            ordinary guest-targeted includes the consumer adds.
# ===========================================================================
{
  den,
  config,
  lib,
  inputs,
  ...
}:
let
  inherit (den.lib.policy) resolve route mkPolicy;

  guestKind = "delivered-guest";

  cfg = config.den.deliveredChild;

  # An include entry's stable identifier, used for OMIT filtering. Named
  # policy includes carry `.name`; bare functions/attrsets have none.
  includeName = inc: if builtins.isAttrs inc && inc ? name then inc.name else null;

  # CURATED includes for the guest kind, DERIVED from host.includes so the
  # guest tracks the host's participation surface minus the omitted entries.
  # (Read host.includes; we never write back to it from here, so no cycle.)
  hostIncludes = config.den.schema.host.includes or [ ];
  curatedFromHost = builtins.filter (
    inc:
    let
      n = includeName inc;
    in
    n == null || !(builtins.elem n cfg.omitIncludeNames)
  ) hostIncludes;

  # The guest class is always nixos, so the hardcoded `.nixosModules` accessor
  # is correct here. Used as the home-manager module default pinned on a raw
  # guest record (which bypasses the host submodule's option defaults — gap G6).
  hmNixosModule = inputs.home-manager.nixosModules.home-manager;

  # A nixos stateVersion default for the delivered guest, kept as an option
  # contract for consumers. den.default's nixos content now DOES emit at the
  # guest scope (the guest authors honest nixos), but a guest may still want an
  # explicit stateVersion independent of the fleet default. Plain assignment
  # matches the historical behavior; set stateVersion to null to apply none.
  guestDefault = lib.optional (cfg.stateVersion != null) {
    name = "delivered-guest-default";
    nixos.system.stateVersion = cfg.stateVersion;
  };

  # Per-user home-manager synthesis bridge for the delivered guest.
  #
  # The STANDARD home-manager battery fires for the guest naturally (guest
  # class = nixos, host.home-manager.enable defaulted true below), but it
  # forwards each user's homeManager content from a NESTED user-under-guest
  # resolve sub-scope via a per-scope forward-route. Simple routes (the delivery
  # route) collect from the ORIGINAL pre-route per-scope state, so the battery's
  # user-scope append is invisible to the delivery route's collection. Worse,
  # the user-under-guest scope sits BELOW the isolated guest, so isolation drops
  # that battery copy from the parent entirely.
  #
  # This policy bridges the gap at the GUEST HOST scope (which IS the delivery
  # route's collection root): it RESOLVES each homeManager user's homeManager
  # content (den.lib.aspects.resolveImports — the same resolver the battery
  # forward uses) and emits it as nixos config under home-manager.users.<user>
  # as a `{ imports = [...]; }` module. The guest's real home-manager module
  # (host.home-manager.module) evaluates those imports when the microvm
  # RE-INSTANTIATES the delivered config as the guest's own nixosSystem —
  # exactly the standard home-manager.users.<u> submodule contract. There is no
  # double-delivery: the battery-forward copy is dropped by isolation.
  guestHmUserForward =
    { host, ... }:
    let
      hmUsers = lib.filter (u: lib.elem "homeManager" (u.classes or [ ])) (
        lib.attrValues (host.users or { })
      );
      userHmModule =
        user:
        den.lib.aspects.resolveImports "homeManager" (den.lib.resolveEntity "user" { inherit host user; });
    in
    [
      (den.lib.policy.include {
        nixos.home-manager.users = lib.listToAttrs (
          map (user: lib.nameValuePair user.userName (userHmModule user)) hmUsers
        );
      })
    ];

  # The guest kind's includes: curated host participation + the per-user
  # home-manager synthesis bridge + the expose policy + a stateVersion default.
  curatedIncludes =
    curatedFromHost
    ++ [
      (mkPolicy "guest-hm-user-forward" guestHmUserForward)
      (mkPolicy "expose-child-quirks" exposePolicy)
    ]
    ++ guestDefault;

  # The home-manager module pinned by the raw guest record. Materialized here
  # because a RAW delivered guest bypasses the host submodule (gap G6), so the
  # `home-manager.enable`/`.module` option DEFAULTS the standard battery's
  # hostConf defines never apply to the `host` binding. We replicate those
  # defaults on the raw guest record below (mirroring nix/lib/home-env.nix:
  # hostOptions) so:
  #   - mkDetectHost sees `host.home-manager.enable` = true (a homeManager user
  #     exists) and does not short-circuit, and
  #   - the battery's hostModule can read `host.home-manager.module`.
  guestHmModule = hmNixosModule;
  guestHasHmUser =
    guest:
    builtins.any (u: builtins.elem "homeManager" (u.classes or [ ])) (
      builtins.attrValues (guest.users or { })
    );

  # Delivery route, registered INSIDE the guest scope (sourceScopeId = guest =
  # collection root); appendToParent lands the wrapped result at the parent.
  # Gated against re-fire in nested sub-scopes (user/home), where it would
  # self-deliver the guest's content into its own nixos.
  deliverPolicyFor =
    name:
    mkPolicy "deliver-child-${name}" (
      { ... }@args:
      lib.optionals (!(args ? user) && !(args ? home)) [
        (route {
          fromClass = "nixos";
          intoClass = "nixos";
          collectSubtree = true;
          appendToParent = true;
          path = cfg.deliveryPathFor name;
          # The delivery target (microvm.vms.<name>.config) RE-INSTANTIATES the
          # collected nixos as its own NixOS system, so deliver the keyed module
          # wrappers verbatim (base-module defaults apply at the target, keys
          # dedup {host,user}-scope re-declarations) instead of pre-evaluating
          # them into resolved config (which strips defaults + keys).
          reinstantiate = true;
        })
      ]
    );

  # Per-child delivery: resolve the guest as a nested isolated child entity
  # authoring honest nixos, carrying its own delivery route into the guest
  # scope. Rebinding `host` to the guest makes curated host-includes and the
  # standard home-manager battery see the guest as `host`.
  resolveChild =
    name: guest:
    let
      # Default the home-manager host option on the raw guest unless the guest
      # already declares it (consumer override wins).
      hmDefault = lib.optionalAttrs (!(guest ? home-manager)) {
        home-manager = {
          enable = guestHasHmUser guest;
          module = guestHmModule;
        };
      };
      withClass =
        guest
        // hmDefault
        // {
          class = "nixos";
          intoAttr = [ ];
        };
    in
    resolve.to.withIncludes guestKind [ (deliverPolicyFor name) ] {
      ${guestKind} = withClass;
      host = withClass;
    };

  resolvePolicy = { host, ... }: lib.mapAttrsToList resolveChild (host.deliveredChildren or { });

  # EXPOSE policy — runs inside the GUEST scope (it is part of the guest kind's
  # curated includes, NOT the parent's host.includes). pipe.expose must fire in
  # the scope that EMITS the quirk so the value flows up to the parent. Only
  # quirks registered in den.quirks are exposed; the default set is opt-in (a
  # consumer declares ollama-endpoints / prometheus-targets in its fleet config),
  # and referencing an undeclared quirk is a silent no-op.
  exposePolicy =
    { ... }:
    map (q: den.lib.policy.pipe.from q [ den.lib.policy.pipe.expose ]) (
      builtins.filter (q: den.quirks or { } ? ${q}) cfg.exposeQuirks
    );

  # Parent-host option: explicit, per-parent declaration of delivered children.
  hostConf = {
    options.deliveredChildren = lib.mkOption {
      description = ''
        Guest host entities delivered as nested children of this host. Each
        guest is resolved as an isolated `${guestKind}` child authoring honest
        `nixos`, and its content is routed into this host's configuration at
        `den.deliveredChild.deliveryPathFor <name>` instead of producing a
        standalone flake output.
      '';
      type = lib.types.attrsOf lib.types.raw;
      default = { };
    };
  };
in
{
  config.den.schema.${guestKind} = {
    isEntity = true;
    isolated = true;
    parent = "host";
    includes = curatedIncludes;
  };

  config.den.schema.host.imports = [ hostConf ];

  config.den.policies.resolve-child-host = resolvePolicy;

  # Wire the PARENT resolve policy into every host scope. GATED on
  # host.deliveredChildren so non-parent hosts pay no cost (no-op include →
  # byte-identical toplevel). The delivery route is NOT here — it lives in the
  # guest kind's curated includes so it fires in the guest scope (its own
  # collection root). The expose policy likewise lives in the guest includes.
  config.den.schema.host.includes = [
    den.policies.resolve-child-host
  ];

  options.den.deliveredChild = {
    deliveryPathFor = lib.mkOption {
      description = ''
        Function mapping a child name to the parent-config path the child's
        content is routed into. Defaults to the microvm guest slot
        `microvm.vms.<name>.config`; override for other delivery targets.
      '';
      type = lib.types.functionTo (lib.types.listOf lib.types.str);
      default = name: [
        "microvm"
        "vms"
        name
        "config"
      ];
      defaultText = lib.literalExpression ''name: [ "microvm" "vms" name "config" ]'';
    };
    omitIncludeNames = lib.mkOption {
      description = ''
        Names of host-includes to OMIT from the curated guest kind. The default
        targets nix-config's colmena `host-modules-capture` host-include, which
        runs a `policy.instantiate` producing a standalone OS module list — a
        delivered child must not instantiate.

        NOTE: colmena lives in nix-config (modules/den/batteries/colmena.nix),
        NOT in den, so `host-modules-capture` is NOT a den host-include. This
        omit is therefore a NO-OP in den-only tests (nothing to filter) and is
        only exercised by the nix-config consumer. The name was verified against
        nix-config: `den.policies.host-modules-capture` →
        `den.schema.host.includes`, whose policy `.name` is "host-modules-capture".
      '';
      type = lib.types.listOf lib.types.str;
      default = [ "host-modules-capture" ];
    };
    exposeQuirks = lib.mkOption {
      description = "Fleet quirks exposed from each delivered child up to the parent.";
      type = lib.types.listOf lib.types.str;
      default = [
        "ollama-endpoints"
        "prometheus-targets"
      ];
    };
    stateVersion = lib.mkOption {
      description = ''
        stateVersion default applied in the guest's nixos class. The guest now
        authors honest nixos and den.default's nixos content emits at the guest
        scope, but this provides an explicit per-guest stateVersion contract.
        Set to null to apply none.
      '';
      type = lib.types.nullOr lib.types.str;
      default = null;
    };
  };
}
