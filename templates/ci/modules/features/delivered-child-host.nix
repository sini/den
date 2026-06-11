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

    # ====================================================================
    # INTEGRATION SPIKE: REALISTIC delivered child (real users + agenix +
    # home-manager) to quantify the COMPLETE tailoring surface.
    #
    # A realistic guest (cf. cortex-cuda) has: real users with the
    # homeManager class, the agenix battery (host.public_key read +
    # per-user secrets), and home-manager synthesis. Each of the tests
    # below exercises one of those facets through the delivered child and
    # records the gap + the minimal tailoring fix.
    #
    # ---- GAP TABLE (host-include attr / break-reason / tailoring fix) ----
    #
    # G1  host.users (core host-to-users)
    #     Break-reason: resolve.shared { user } runs for guest-os class too,
    #     so users DO synthesize into the child scope — NO break. But their
    #     content lands in the user's home/homeManager class, not guest-os,
    #     so it is NOT collected by the guest-os route. The OS-level user
    #     account (users.users.<name>) is emitted into ${host.class} =
    #     guest-os by whatever define-user/os-user battery targets the host
    #     class — that DOES land in guest-os and IS collected. SAFE once the
    #     route collects guest-os; no per-attr tailoring needed.
    #
    # G2  home-manager battery host-include (home-env makeHomeEnv policyFn)
    #     Break-reason: gated off — mkDetectHost requires host.class ∈
    #     {nixos,darwin}; guest-os fails isOsSupported, so policyFn → [].
    #     home-manager synthesis SILENTLY DOES NOT FIRE for a guest-os child.
    #     Tailoring fix (to actually GET home-manager in the guest): the
    #     guest's distinct class must be home-manager-supported. Either set
    #     guest.class = "nixos" (loses the route isolation — bad) OR register
    #     a home-env instance whose supportedOses includes "guest-os" and
    #     whose getModule resolves a real module. This is the ONE structural
    #     tailoring beyond a clean attr-override: a per-class home-env wiring.
    #
    # G3  agenix host.public_key (battery readFile)
    #     Break-reason: builtins.readFile host.public_key hard-blocks when
    #     public_key is unset (proven by -verbatim-blocks above).
    #     Tailoring fix: set guest.public_key to a real key path (parent's or
    #     the guest's own). Clean attr override.
    #
    # G4  agenix per-user secrets (host.<class>.age.secrets.* with paths)
    #     Break-reason: if the battery synthesises secret file paths from a
    #     per-host secrets dir keyed by host.name, a guest whose name has no
    #     secrets dir readFiles a missing path → eval block, same shape as G3.
    #     Tailoring fix: point the guest's secrets source at the parent's (or
    #     declare the guest's own). Clean attr override (data path).
    #
    # G5  den.default host-include (defaults.nix)
    #     Break-reason: den.default sets nixos.system.stateVersion +
    #     homeManager.home.stateVersion. For a guest-os child these land in
    #     the nixos/homeManager classes, NOT guest-os, so the route does not
    #     collect them: the guest's guest-os config gets NO stateVersion
    #     default. NOT an eval break, but a silent missing-default.
    #     Tailoring fix: add a guest-os-targeted default
    #     (den.default.guest-os.system.stateVersion) OR have the guest aspect
    #     set it. Clean attr addition.
    #
    # G6  user records (name / userName / classes) — NEW, discovered here.
    #     Break-reason: a delivered child built as a RAW entity attrset and
    #     handed to resolve.to "host" { host = guest; } does NOT pass through
    #     the host submodule's userType, which is what synthesises each user's
    #     name/userName/classes. The core host-to-users policy then does
    #     `user.name` (core.nix:30) on a bare { } and HARD-BLOCKS:
    #       error: attribute 'name' missing  (modules/policies/core.nix:30).
    #     This bites EVERY realistic guest the moment it declares ≥1 user.
    #     Tailoring fix: declare each guest user as a FULL record
    #     ({ name; userName; classes; }) — i.e. hand-synthesise the fields the
    #     standalone-host path gets for free. Clean (verbose) attr override.
    #     ARCHITECTURAL NOTE: this is the single biggest argument that "raw
    #     entity as host" is leaky — the guest is NOT coerced through hostType,
    #     so it silently lacks name/system/class/intoAttr defaults too (the
    #     spike's mkGuest already hand-sets system/class/intoAttr for exactly
    #     this reason). A dedicated guest kind (or routing the guest through a
    #     real entity submodule) would restore those defaults.
    # ---------------------------------------------------------------------

    # G3+G4: realistic agenix — host.public_key set to a real path AND a
    # per-user secret path; both readFiles resolve through the child.
    # NOTE the users entry is a FULL record (name/userName/classes): a raw
    # delivered-child entity bypasses the host submodule's userType, so the
    # core host-to-users policy reads user.name off the raw attrset — see G6.
    test-delivered-child-realistic-agenix = denTest (
      { den, igloo, ... }:
      let
        guest = mkGuest den {
          public_key = ./delivered-child-host.nix;
          users.tux = {
            name = "tux";
            userName = "tux";
            classes = [ "homeManager" ];
          };
        };
        # Mirrors a real agenix battery: host pubkey + a per-user secret
        # whose source path is derived (here, a real file that exists).
        agenixBattery =
          { host, ... }:
          {
            guest-os.age.hostPubkey = builtins.readFile host.public_key;
            guest-os.age.secrets."tux-password".file = host.public_key;
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
          agenixBattery
        ];
        den.aspects.guest-aspect.guest-os.networking.hostName = "guest-vm";

        expr = {
          pubkeyResolved = igloo.microvm.vms.guest.config.age.hostPubkey != "";
          secretPresent = igloo.microvm.vms.guest.config.age.secrets ? "tux-password";
          hn = igloo.microvm.vms.guest.config.networking.hostName;
        };
        expected = {
          pubkeyResolved = true;
          secretPresent = true;
          hn = "guest-vm";
        };
      }
    );

    # G1: real users on the guest. host-to-users (core) fires for the
    # guest-os child; the OS-level account, emitted into the host class
    # (guest-os), is collected by the route and arrives in the delivered
    # config. No per-attr tailoring; SAFE.
    test-delivered-child-realistic-users = denTest (
      { den, igloo, ... }:
      let
        guest = mkGuest den {
          # FULL record — raw delivered-child entity bypasses userType (G6).
          users.tux = {
            name = "tux";
            userName = "tux";
            classes = [ "homeManager" ];
          };
        };
        # An os-user-style host-include that writes the account into the
        # host class (guest-os), the way an os-user battery would.
        osUserLike =
          { host, ... }:
          {
            guest-os.users.users = builtins.mapAttrs (name: _: {
              isNormalUser = true;
            }) host.users;
          };
      in
      {
        den.classes.guest-os.description = "delivered child host class";
        den.aspects.igloo.includes = [ den.aspects.microvm-slot ];
        den.aspects.microvm-slot.nixos.imports = [ microvmSlot ];
        den.hosts.x86_64-linux.igloo = { };

        den.policies.deliver-guest = deliverGuest den guest;
        den.schema.host.includes = [
          den.policies.deliver-guest
          osUserLike
        ];
        den.aspects.guest-aspect.guest-os.networking.hostName = "guest-vm";

        expr = {
          hasTux = igloo.microvm.vms.guest.config.users.users ? tux;
          isNormal = igloo.microvm.vms.guest.config.users.users.tux.isNormalUser or false;
        };
        expected = {
          hasTux = true;
          isNormal = true;
        };
      }
    );

    # G5: den.default stateVersion does NOT reach the guest-os class (lands
    # in nixos/homeManager class, not collected). A guest-os-targeted
    # default is the tailoring; here we set it on the guest aspect and
    # confirm it arrives.
    test-delivered-child-realistic-stateversion = denTest (
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

        den.aspects.guest-aspect.guest-os = {
          networking.hostName = "guest-vm";
          # The tailoring: a guest-os-targeted stateVersion (den.default's
          # nixos.* default does not reach this class).
          system.stateVersion = "25.11";
        };

        expr = igloo.microvm.vms.guest.config.system.stateVersion;
        expected = "25.11";
      }
    );

  };
}
