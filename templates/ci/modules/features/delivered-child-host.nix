# SPIKE: delivered child host — a microvm-style guest that resolves as a child
# host scope nested under its parent host, realized INTO the parent's config
# (microvm.vms.<name>.config) instead of a standalone nixosConfigurations output.
#
# HARNESS NOTE: denTest only exposes INSTANTIATED hosts
# (config.flake.nixosConfigurations.<name>.config). A delivered child has NO
# denTest handle, so EVERY assertion observes the child THROUGH the parent's
# instantiated output (`igloo`), by reading a child-sourced value back out of
# `igloo.<parent-config-path>` (here igloo.microvm.vms.guest.config.*).
#
# ============================ DECISION (spike findings) =====================
#
# (a) DELIVERY CHANNEL — route + collectSubtree (NO den-core change):
#
#     The originally-hypothesised channel (redirect an entity's instantiate to
#     write a flake-option path like
#     flake.nixosConfigurations.igloo.config.microvm.vms.guest.config) is DEAD.
#     flake-parts' nixosConfigurations is `lazyAttrsOf raw`: each entry is an
#     opaque, already-evaluated nixosSystem. Writing into its `.config` subpath
#     does NOT inject a module into that nixosSystem — it collides with the
#     read-only evaluation result. (Proven: the delivered { imports = …; } landed
#     as a literal value, NOT merged into the parent's config.)
#
#     The channel that WORKS uses three EXISTING den-core mechanisms, composed:
#
#       1. resolve.to "host" { host = guest }
#          The guest is a host-KIND entity, so it nests under the parent's host
#          scope and inherits den.schema.host.includes (host-to-users, batteries,
#          den.default). resolveEntity reads ctx.host.aspect, so the child's own
#          aspect tree is walked too. (Finding: a host child nested under igloo
#          leaks its class content into igloo's subtree — see mechanism 2.)
#
#       2. guest.class = "guest-os" (a DISTINCT class, registered via
#          den.classes.guest-os). Because resolveEntityClass derives the scope
#          class from the entity's `class`, the child's walked content lands in
#          the `guest-os` class — ISOLATED from igloo's own `nixos`. Without this
#          the child's modules would flatten into igloo's top-level nixos config.
#
#       3. policy.route { fromClass = "guest-os"; intoClass = "nixos";
#                         collectSubtree = true;
#                         path = [ "microvm" "vms" "guest" "config" ]; }
#          collectSubtree (route/apply.nix applySimpleRoute) collects guest-os
#          content from the ENTIRE parent subtree — including the child scope —
#          and nests it under microvm.vms.guest.config in igloo's nixos class
#          BEFORE igloo is instantiated. This is the realization-delivery channel:
#          module-into-parent-module-set, the same path-nesting `route`/`forward`
#          already use (cf. features/route.nix test-route-class-into-subpath and
#          features/dynamic-intopath.nix). NO resolve.nix / instantiate delta.
#
#     The child sets intoAttr = [] and is given NO policy.instantiate, so it
#     produces NO standalone nixosConfigurations.<name> output; only the parent
#     is instantiated, and it carries the child inside its config.
#
# (b) KIND — reuse `host`, TAILORED (NOT a new `delivered-child` kind):
#
#     Reusing the host kind is what gives the child den.schema.host.includes for
#     free. The ONLY friction is host-includes that assume host-submodule-
#     synthesised attrs the bare child lacks:
#       - host.users  (host-to-users) — supply users = {}.
#       - host.<class>.module (home-manager battery hostModule) — fires only when
#         a user with the home class is present; a userless guest gates it off.
#       - the agenix battery's `hostPubkey = builtins.readFile host.public_key`
#         — a readFile on a missing/nonexistent key path is an EVAL ERROR the
#         moment the value is forced through the parent.
#     Finding: that hard-block is NOT intrinsic to den-core or the host kind — it
#     comes from the agenix battery (opt-in via includes; absent on this branch).
#     A delivered child therefore reuses `host` and simply TAILORS the conflicting
#     attrs: set public_key (and secret paths) to the parent's, so the readFile
#     resolves (test-delivered-child-agenix-tailored). A verbatim host without
#     them hard-blocks (test-delivered-child-agenix-verbatim-blocks). A new kind
#     would only be warranted to STRIP host-only includes wholesale — the spike
#     did not find that necessary; per-attr tailoring suffices.
# ============================================================================
{ denTest, lib, ... }:
let
  # Stub of the microvm.vms.<name>.config slot the real microvm.nixos module
  # provides on the PARENT. Freeform so delivered child config can land here.
  microvmSlot =
    { lib, ... }:
    {
      options.microvm.vms = lib.mkOption {
        type = lib.types.attrsOf (
          lib.types.submodule {
            options.config = lib.mkOption {
              type = lib.types.submoduleWith {
                modules = [
                  { config._module.freeformType = lib.types.lazyAttrsOf lib.types.anything; }
                ];
              };
              default = { };
            };
          }
        );
        default = { };
      };
    };

  # A delivered-child guest entity: host KIND, distinct class, no standalone
  # output. `extra` lets individual tests tailor it (e.g. public_key).
  mkGuest =
    den: extra:
    {
      name = "guest";
      system = "x86_64-linux";
      class = "guest-os";
      users = { };
      intoAttr = [ ];
      aspect = den.aspects.guest-aspect;
    }
    // extra;

  # The deliver policy: resolve the guest as a nested host child, then route its
  # guest-os content into the parent's nixos under microvm.vms.guest.config.
  deliverGuest =
    den: guest:
    { host, ... }:
    let
      inherit (den.lib.policy) resolve route;
    in
    lib.optionals (host.name == "igloo") [
      (resolve.to "host" { host = guest; })
      (route {
        fromClass = "guest-os";
        intoClass = "nixos";
        collectSubtree = true;
        path = [
          "microvm"
          "vms"
          "guest"
          "config"
        ];
      })
    ];
in
{
  flake.tests.delivered-child-host = {

    # STEP 1 (CRUX): the realization-delivery channel.
    # Parent igloo (instantiated) resolves a child guest whose realization is
    # delivered into igloo.microvm.vms.guest.config. Assert a child-ONLY value
    # (the child's hostName) is readable THROUGH the parent. Resolved ONCE.
    test-delivered-child-redirect-instantiate = denTest (
      { den, igloo, ... }:
      let
        guest = mkGuest den { };
      in
      {
        den.classes.guest-os.description = "delivered child host class";
        den.aspects.igloo.includes = [ den.aspects.microvm-slot ];
        den.aspects.microvm-slot.nixos.imports = [ microvmSlot ];
        den.hosts.x86_64-linux.igloo = { };

        den.policies.deliver-guest = deliverGuest den guest;
        den.schema.host.includes = [ den.policies.deliver-guest ];

        den.aspects.guest-aspect.guest-os.networking.hostName = "guest-vm";

        # Observe the child THROUGH the parent's instantiated config.
        expr = igloo.microvm.vms.guest.config.networking.hostName;
        expected = "guest-vm";
      }
    );

    # STEP 2a: participation — a den.schema.host.includes value fires in the
    # CHILD scope and arrives in the delivered config through the parent.
    test-delivered-child-participation = denTest (
      { den, igloo, ... }:
      let
        guest = mkGuest den { };
      in
      {
        den.classes.guest-os.description = "delivered child host class";
        den.aspects.igloo.includes = [ den.aspects.microvm-slot ];
        den.aspects.microvm-slot.nixos.imports = [ microvmSlot ];
        den.hosts.x86_64-linux.igloo = { };

        den.policies.deliver-guest = deliverGuest den guest;
        # A host-include emitting into guest-os fires for EVERY host scope,
        # the child guest included.
        den.schema.host.includes = [
          den.policies.deliver-guest
          { guest-os.boot.kernelModules = [ "from-host-include" ]; }
        ];

        den.aspects.guest-aspect.guest-os.networking.hostName = "guest-vm";

        expr = {
          hn = igloo.microvm.vms.guest.config.networking.hostName;
          km = igloo.microvm.vms.guest.config.boot.kernelModules;
        };
        expected = {
          hn = "guest-vm";
          km = [ "from-host-include" ];
        };
      }
    );

    # STEP 2b: expose — child emits a quirk + pipe.expose; igloo consumes it.
    test-delivered-child-expose = denTest (
      { den, igloo, ... }:
      let
        inherit (den.lib.policy) pipe;
        guest = mkGuest den { };
      in
      {
        den.classes.guest-os.description = "delivered child host class";
        den.quirks.guest-ports.description = "ports the guest needs forwarded upward";
        den.aspects.igloo.includes = [
          den.aspects.microvm-slot
          den.aspects.port-consumer
        ];
        den.aspects.microvm-slot.nixos.imports = [ microvmSlot ];
        den.hosts.x86_64-linux.igloo = { };

        den.policies.deliver-guest = deliverGuest den guest;
        den.policies.expose-ports = { host, ... }: [ (pipe.from "guest-ports" [ pipe.expose ]) ];
        den.schema.host.includes = [
          den.policies.deliver-guest
          den.policies.expose-ports
        ];

        # Child emits the quirk; parent consumes the exposed value.
        den.aspects.guest-aspect = {
          guest-os.networking.hostName = "guest-vm";
          guest-ports = [ 2222 ];
        };
        den.aspects.port-consumer.nixos =
          { guest-ports, ... }:
          {
            networking.firewall.allowedTCPPorts = guest-ports;
          };

        expr = igloo.networking.firewall.allowedTCPPorts;
        expected = [ 2222 ];
      }
    );

    # STEP 2c: no standalone output — child has intoAttr = [] and no
    # policy.instantiate, so nixosConfigurations.guest does NOT exist; only the
    # parent is instantiated.
    test-delivered-child-no-standalone-output = denTest (
      { den, config, ... }:
      let
        guest = mkGuest den { };
      in
      {
        den.classes.guest-os.description = "delivered child host class";
        den.aspects.igloo.includes = [ den.aspects.microvm-slot ];
        den.aspects.microvm-slot.nixos.imports = [ microvmSlot ];
        den.hosts.x86_64-linux.igloo = { };

        den.policies.deliver-guest = deliverGuest den guest;
        den.schema.host.includes = [ den.policies.deliver-guest ];
        den.aspects.guest-aspect.guest-os.networking.hostName = "guest-vm";

        expr = {
          iglooExists = config.flake.nixosConfigurations ? igloo;
          guestExists = config.flake.nixosConfigurations ? guest;
        };
        expected = {
          iglooExists = true;
          guestExists = false;
        };
      }
    );

    # STEP 2d (kind driver, POSITIVE): tailored child. The agenix-like
    # host-include reads `host.public_key` via builtins.readFile; the child sets
    # public_key to the parent's existing key path, so it resolves and the value
    # lands in the delivered config. Proves reuse-`host`-tailored works.
    test-delivered-child-agenix-tailored = denTest (
      { den, igloo, ... }:
      let
        guest = mkGuest den { public_key = ./delivered-child-host.nix; };
        agenixLike =
          { host, ... }:
          {
            guest-os.age.hostPubkey = builtins.readFile host.public_key;
          };
      in
      {
        den.classes.guest-os.description = "delivered child host class";
        den.aspects.igloo.includes = [ den.aspects.microvm-slot ];
        den.aspects.microvm-slot.nixos.imports = [ microvmSlot ];
        den.hosts.x86_64-linux.igloo.public_key = ./delivered-child-host.nix;

        den.policies.deliver-guest = deliverGuest den guest;
        den.schema.host.includes = [
          den.policies.deliver-guest
          agenixLike
        ];
        den.aspects.guest-aspect.guest-os.networking.hostName = "guest-vm";

        # The readFile resolved (non-empty) AND the child's own value is present.
        expr =
          igloo.microvm.vms.guest.config.age.hostPubkey != ""
          && igloo.microvm.vms.guest.config.networking.hostName == "guest-vm";
        expected = true;
      }
    );

    # STEP 2d (kind driver, NEGATIVE): verbatim child. WITHOUT public_key, the
    # agenix-like readFile host-include hard-blocks eval (EvalError on the missing
    # attr) the moment the delivered value is forced through the parent. This is
    # WHY tailoring (not a separate kind, but per-attr override) is required.
    test-delivered-child-agenix-verbatim-blocks = denTest (
      { den, igloo, ... }:
      let
        guest = mkGuest den { }; # NO public_key.
        agenixLike =
          { host, ... }:
          {
            guest-os.age.hostPubkey = builtins.readFile host.public_key;
          };
      in
      {
        den.classes.guest-os.description = "delivered child host class";
        den.aspects.igloo.includes = [ den.aspects.microvm-slot ];
        den.aspects.microvm-slot.nixos.imports = [ microvmSlot ];
        den.hosts.x86_64-linux.igloo.public_key = ./delivered-child-host.nix;

        den.policies.deliver-guest = deliverGuest den guest;
        den.schema.host.includes = [
          den.policies.deliver-guest
          agenixLike
        ];
        den.aspects.guest-aspect.guest-os.networking.hostName = "guest-vm";

        # Forcing the agenix value from the verbatim child subtree hard-blocks.
        expr = igloo.microvm.vms.guest.config.age.hostPubkey;
        expectedError = {
          type = "EvalError";
          msg = "public_key";
        };
      }
    );

  };
}
