# Delivered child host — a reusable primitive for nesting a *guest* host
# inside a *parent* host's instantiated configuration (e.g. a microvm guest
# realized into parent.microvm.vms.<name>.config) instead of producing a
# standalone nixosConfigurations.<name> output.
#
# ===================== DESIGN (resolved by two spikes) =====================
#
# DELIVERY = resolve + class-isolation + route+collectSubtree. NO den-core
# (nix/) change. Three EXISTING mechanisms composed:
#
#   1. resolve.to "<guest-kind>" { delivered-guest = guest; host = guest; }
#      nests the guest as a child entity scope under the parent host. The
#      `host` binding lets curated host-include policies (host-to-users, the
#      home batteries, den.default) fire for the guest; the `delivered-guest`
#      binding makes resolveEntityClass derive the guest's distinct class.
#
#   2. guest.class = "guest-os" (a DISTINCT class) isolates the child's walked
#      content from the parent's own `nixos` partition. Without it the guest's
#      modules flatten into the parent's top-level nixos config.
#
#   3. route { fromClass = "guest-os"; intoClass = "nixos"; collectSubtree;
#             path = [ "microvm" "vms" "<name>" "config" ]; } collects the
#      guest-os content from the ENTIRE parent subtree (incl. the child scope)
#      and nests it under the delivery path in the parent's nixos class BEFORE
#      the parent is instantiated. The guest carries intoAttr = [] and gets NO
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
#   INHERIT  participation/identity/collect includes (host-to-users, the home
#            batteries, den.default).
#   OMIT     includes producing a standalone instantiate output (nix-config's
#            colmena host-modules-capture) — a child must not instantiate. Named
#            via `den.deliveredChild.omitIncludeNames`. No-op in den-only tests
#            (colmena is a nix-config host-include, not a den one).
#   RETARGET / OVERRIDE  agenix-style host-includes whose class lookup or key
#            paths assume the host class: the consumer points public_key /
#            secret sources at the parent and targets guest-os. Expressed as
#            ordinary guest-targeted includes the consumer adds.
#   ADD      a guest-os home-env instance (supportedOses ∋ guest-os) so
#            home-manager synthesis fires for the guest, plus a guest-os
#            stateVersion default.
# ===========================================================================
{
  den,
  config,
  lib,
  inputs,
  ...
}:
let
  inherit (den.lib.policy) resolve route;

  guestClass = "guest-os";
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

  # The guest class is always nixos-flavored, so the hardcoded `.nixosModules`
  # accessor is correct here (vs the class-keyed `"${host.class}Modules"` that
  # the normal host battery uses — guest-os has no *Modules input attr of its own).
  hmNixosModule = inputs.home-manager.nixosModules.home-manager;

  # ADD: a guest-os home-env instance so home-manager synthesis (gated on
  # host.class ∈ supportedOses) fires for a guest-os child. getModule pins the
  # parent's nixos home-manager module (the guest-os class has no *Modules
  # input attr of its own).
  #
  # makeHomeEnv returns THREE parts that are ALL wired (mirroring
  # modules/aspects/batteries/home-manager.nix for the normal host):
  #   - guestHome.hostConf   → the guest kind's host-submodule imports
  #     (den.schema.delivered-guest.imports). Defines the `home-manager.enable`
  #     /`.module` options ON the guest; without them mkDetectHost's
  #     `isEnabled = (host.home-manager or {}).enable or false` is false →
  #     detection short-circuits, and the home-manager module pinned for the
  #     guest's downstream re-instantiation is unavailable.
  #   - guestHome.battery    → the guest kind's includes (host→user detection +
  #     the host-scope home-manager module import into guest-os).
  #   - guestHome.userDetect → the USER kind's includes (per-user detection;
  #     gated on host.class ∈ supportedOses = [guest-os], so a no-op for
  #     non-guest hosts).
  #
  # NOTE: the battery forwards each user's homeManager content from a NESTED
  # user resolve sub-scope; that forward-route does not survive the parent's
  # guest-os collectSubtree delivery route, so the actual per-user delivery is
  # done by guestHmUserForward below (a host-scope bridge).
  guestHome = den.lib.home-env.makeHomeEnv {
    className = "homeManager";
    ctxName = "guest-hm";
    supportedOses = [ guestClass ];
    optionPath = "home-manager";
    getModule = _: hmNixosModule;
    forwardPathFn =
      { user, ... }:
      [
        "home-manager"
        "users"
        user.userName
      ];
  };

  # ADD: a guest-os stateVersion default. den.default targets nixos/homeManager
  # classes, which the guest-os route does not collect, so the guest gets no
  # stateVersion otherwise.
  guestDefault = lib.optional (cfg.stateVersion != null) {
    name = "delivered-guest-default";
    ${guestClass}.system.stateVersion = cfg.stateVersion;
  };

  # Per-user home-manager synthesis for the delivered guest.
  #
  # The home-env BATTERY (guestHome.battery, wired below) detects the guest's
  # homeManager users and forwards each user's homeManager content via a
  # homeManager → guest-os forward-route registered in a NESTED user resolve
  # sub-scope. That sub-scope forward-route does not survive the parent's
  # guest-os → nixos collectSubtree delivery route: forwards register routes
  # that are applied per-scope, and the delivery route's per-module freeform
  # nesting does not re-run them. So the battery alone yields NO
  # home-manager.users content in the delivered config.
  #
  # This policy bridges that gap at the GUEST HOST scope (one level up, where
  # collectSubtree reaches): it RESOLVES each homeManager user's homeManager
  # content (den.lib.aspects.resolveImports — the same resolver the forward
  # uses) and emits it as guest-os config under home-manager.users.<user> as a
  # `{ imports = [...]; }` module. The guest's real home-manager module
  # (host.home-manager.module, pinned by the consumer / getModule) evaluates
  # those imports when the microvm RE-INSTANTIATES the delivered config as the
  # guest's own nixosSystem — exactly the standard home-manager.users.<u>
  # submodule contract.
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
        ${guestClass}.home-manager.users = lib.listToAttrs (
          map (user: lib.nameValuePair user.userName (userHmModule user)) hmUsers
        );
      })
    ];

  # The guest kind's includes: curated host participation + the guest home-env
  # (host-submodule options + host→user routing) + the per-user home-manager
  # synthesis bridge + a guest-os stateVersion default + the expose policy.
  curatedIncludes =
    curatedFromHost
    ++ [
      guestHome.battery
      (den.lib.policy.mkPolicy "guest-hm-user-forward" guestHmUserForward)
      (den.lib.policy.mkPolicy "expose-child-quirks" exposePolicy)
    ]
    ++ guestDefault;

  # The guest-os home-env module pinned by getModule. Materialized here because
  # a RAW delivered guest bypasses the host submodule (gap G6), so the
  # `home-manager.enable`/`.module` option DEFAULTS that guestHome.hostConf
  # defines never apply to the `host` binding. We replicate those defaults on
  # the raw guest record below (mirroring nix/lib/home-env.nix:hostOptions) so:
  #   - mkDetectHost sees `host.home-manager.enable` = true (a homeManager user
  #     exists) and does not short-circuit, and
  #   - the battery's hostModule can read `host.home-manager.module`.
  guestHmModule = hmNixosModule;
  guestHasHmUser =
    guest:
    builtins.any (u: builtins.elem "homeManager" (u.classes or [ ])) (
      builtins.attrValues (guest.users or { })
    );

  # Per-child delivery: resolve the guest as a nested child entity, isolate it
  # in the guest-os class, and route its content into the parent under the
  # delivery path.
  resolveChild =
    _name: guest:
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
          class = guestClass;
          intoAttr = [ ];
        };
    in
    resolve.to guestKind {
      ${guestKind} = withClass;
      host = withClass;
    };

  routeChild =
    name: _guest:
    route {
      fromClass = guestClass;
      intoClass = "nixos";
      collectSubtree = true;
      path = cfg.deliveryPathFor name;
    };

  resolvePolicy = { host, ... }: lib.mapAttrsToList resolveChild (host.deliveredChildren or { });

  routePolicy = { host, ... }: lib.mapAttrsToList routeChild (host.deliveredChildren or { });

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
        guest is resolved in the `${guestClass}` class and routed into this
        host's configuration at `den.deliveredChild.deliveryPathFor <name>`
        instead of producing a standalone flake output.
      '';
      type = lib.types.attrsOf lib.types.raw;
      default = { };
    };
  };
in
{
  config.den.classes.${guestClass}.description = "Delivered child guest host class";

  config.den.schema.${guestKind} = {
    isEntity = true;
    parent = "host";
    includes = curatedIncludes;
    # The guest-os home-env's host-submodule options (home-manager.enable /
    # .module) must exist ON the guest, or mkDetectHost short-circuits and no
    # synthesis fires. Mirrors `den.schema.host.imports = [ result.hostConf ]`
    # in the normal home-manager battery, scoped to the guest kind.
    imports = [ guestHome.hostConf ];
  };

  # The guest-os home-env's per-user detection. Gated on
  # host.class ∈ [guest-os], so it is a no-op for ordinary nixos/darwin users.
  # Mirrors `den.schema.user.includes = [ result.userDetect ]`.
  config.den.schema.user.includes = [ guestHome.userDetect ];

  config.den.schema.host.imports = [ hostConf ];

  config.den.policies.resolve-child-host = resolvePolicy;
  config.den.policies.route-child-host = routePolicy;

  # Wire the PARENT delivery policies into every host scope. Both are GATED on
  # host.deliveredChildren so non-parent hosts pay no cost (no-op include →
  # byte-identical toplevel). The expose policy is NOT here — it lives in the
  # guest kind's curated includes so pipe.expose fires in the guest scope that
  # emits the quirk.
  config.den.schema.host.includes = [
    den.policies.resolve-child-host
    den.policies.route-child-host
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
        stateVersion default applied in the guest-os class (den.default's
        nixos/homeManager defaults are not collected by the guest route). Set
        to null to apply none.
      '';
      type = lib.types.nullOr lib.types.str;
      default = null;
    };
  };
}
