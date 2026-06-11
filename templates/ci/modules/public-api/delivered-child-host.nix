# Acceptance tests for the delivered-child-host PRIMITIVE
# (modules/policies/delivered-child-host.nix).
#
# A delivered child is a guest host that resolves as an ISOLATED nested child
# scope under its parent host and is realized INTO the parent's config
# (microvm.vms.<name>.config) instead of producing a standalone
# nixosConfigurations.<name> output. The guest authors honest `nixos`; an
# entity-isolation marker keeps that content out of the parent's own toplevel,
# and a collect/append-decoupled delivery route lands it at the delivery path.
#
# HARNESS NOTE: denTest only exposes INSTANTIATED hosts
# (config.flake.nixosConfigurations.<name>.config). A delivered child has NO
# denTest handle, so EVERY assertion observes the child THROUGH the parent's
# instantiated output (`igloo`), reading a child-sourced value back out of
# `igloo.microvm.vms.<name>.config.*`.
#
# The primitive supplies: a parent option (host.deliveredChildren), a dedicated
# isolated `delivered-guest` kind whose includes are a curated subset of
# den.schema.host.includes, the delivery policy (resolve + isolation +
# route+collectSubtree+appendToParent), and an expose policy. Tests use the
# primitive — they declare children via den.hosts.<sys>.igloo.deliveredChildren
# rather than hand-rolling the resolve/route pair.
{ denTest, lib, ... }:
let
  # Minimal stand-in for the home-manager nixos module, used only to satisfy
  # the guest's host-submodule home-manager.module option (detection). The real
  # home-manager module self-references `config.home-manager` and only resolves
  # when the guest is re-instantiated as its own nixosSystem; these unit tests
  # never re-instantiate (the guest's nixos content is collected into the
  # freeform microvm slot), so the per-user home-manager modules the primitive
  # emits are re-evaluated explicitly in the assertion instead. Real consumers
  # (nix-config) use the real home-manager module when the microvm genuinely
  # instantiates.
  hmStub = {
    options.home-manager.users = lib.mkOption {
      type = lib.types.lazyAttrsOf (
        lib.types.submodule { freeformType = lib.types.lazyAttrsOf lib.types.anything; }
      );
      default = { };
    };
  };

  # Stub of the microvm.vms.<name>.config slot the real microvm.nixos module
  # provides on the PARENT. Freeform so delivered child config lands here.
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

  # Stub of the agenix `age.*` options. Host-includes authored `nixos.age.*`
  # now fire at the PARENT scope as well as the guest scope (the guest authors
  # honest nixos), where a real nixosSystem has no age options. This absorbs
  # those option writes on the parent.
  ageStub =
    { lib, ... }:
    {
      options.age = lib.mkOption {
        type = lib.types.lazyAttrsOf lib.types.anything;
        default = { };
      };
    };

  # A guest entity. The primitive sets class/intoAttr; the realistic gap-table
  # (G6) still applies: a raw delivered child bypasses the host submodule's
  # userType, so user records must be FULL ({ name; userName; classes; }).
  mkGuest =
    den: extra:
    {
      name = "guest";
      system = "x86_64-linux";
      users = { };
      aspect = den.aspects.guest-aspect;
    }
    // extra;

  # Common parent wiring: the microvm slot + age stub on igloo. Returned as a
  # module so it merges (NOT `//`, which would clobber the test body's own
  # `den` attr).
  parentBase = den: {
    den.aspects.igloo.includes = [ den.aspects.microvm-slot ];
    den.aspects.microvm-slot.nixos.imports = [
      microvmSlot
      ageStub
    ];
  };
in
{
  flake.tests.delivered-child-host = {

    # DELIVERY (crux): parent reads a child-ONLY value back through its
    # instantiated config. Declared purely via the primitive's parent option.
    test-delivery = denTest (
      { den, igloo, ... }:
      {
        imports = [ (parentBase den) ];
        den.hosts.x86_64-linux.igloo.deliveredChildren.guest = mkGuest den { };
        den.aspects.guest-aspect.nixos.networking.hostName = "guest-vm";

        expr = igloo.microvm.vms.guest.config.networking.hostName;
        expected = "guest-vm";
      }
    );

    # PARTICIPATION: a curated host-include value fires in the CHILD scope and
    # arrives in the delivered config. The host-include emits into nixos, so it
    # now fires at the PARENT scope too — assert membership in both, not
    # list-equality (the parent carries nixpkgs defaults like atkbd/loop).
    test-participation = denTest (
      { den, igloo, ... }:
      {
        imports = [ (parentBase den) ];
        den.hosts.x86_64-linux.igloo.deliveredChildren.guest = mkGuest den { };
        den.schema.host.includes = [
          { nixos.boot.kernelModules = [ "from-host-include" ]; }
        ];
        den.aspects.guest-aspect.nixos.networking.hostName = "guest-vm";

        expr = {
          hn = igloo.microvm.vms.guest.config.networking.hostName;
          deliveredHasInclude = lib.elem "from-host-include" igloo.microvm.vms.guest.config.boot.kernelModules;
          parentHasInclude = lib.elem "from-host-include" igloo.boot.kernelModules;
        };
        expected = {
          hn = "guest-vm";
          deliveredHasInclude = true;
          parentHasInclude = true;
        };
      }
    );

    # EXPOSE: child emits a fleet quirk; the primitive's expose policy lifts it
    # to the parent, which consumes it. The quirk is declared + added to the
    # primitive's exposeQuirks set.
    test-expose = denTest (
      { den, igloo, ... }:
      {
        den.quirks.guest-ports.description = "ports the guest needs forwarded upward";
        den.deliveredChild.exposeQuirks = [ "guest-ports" ];

        den.aspects.igloo.includes = [
          den.aspects.microvm-slot
          den.aspects.port-consumer
        ];
        den.aspects.microvm-slot.nixos.imports = [ microvmSlot ];
        den.hosts.x86_64-linux.igloo.deliveredChildren.guest = mkGuest den { };

        den.aspects.guest-aspect = {
          nixos.networking.hostName = "guest-vm";
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

    # NO STANDALONE OUTPUT: the primitive gives the guest intoAttr = [] and no
    # policy.instantiate, so nixosConfigurations.guest does NOT exist; only the
    # parent is instantiated.
    test-no-standalone-output = denTest (
      { den, config, ... }:
      {
        imports = [ (parentBase den) ];
        den.hosts.x86_64-linux.igloo.deliveredChildren.guest = mkGuest den { };
        den.aspects.guest-aspect.nixos.networking.hostName = "guest-vm";

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

    # AGENIX DOESN'T THROW (retarget + parent key): an agenix-like host-include
    # reads host.public_key via builtins.readFile. The guest sets public_key to
    # the parent's existing key path (clean override), so it resolves and the
    # value lands in the delivered config through the parent. The parent
    # (igloo) also sets public_key, so the parent-scope evaluation of the
    # include resolves too (ageStub absorbs the option).
    test-agenix-tailored = denTest (
      { den, igloo, ... }:
      let
        agenixLike =
          { host, ... }:
          {
            nixos.age.hostPubkey = builtins.readFile host.public_key;
          };
      in
      {
        imports = [ (parentBase den) ];
        den.hosts.x86_64-linux.igloo = {
          public_key = ./delivered-child-host.nix;
          deliveredChildren.guest = mkGuest den { public_key = ./delivered-child-host.nix; };
        };
        den.schema.host.includes = [ agenixLike ];
        den.aspects.guest-aspect.nixos.networking.hostName = "guest-vm";

        expr =
          igloo.microvm.vms.guest.config.age.hostPubkey != ""
          && igloo.microvm.vms.guest.config.networking.hostName == "guest-vm";
        expected = true;
      }
    );

    # NEGATIVE (why tailoring is required): a verbatim guest WITHOUT public_key
    # hard-blocks the agenix-like readFile the moment the delivered value is
    # forced through the parent. (igloo itself HAS public_key, so the parent
    # scope is fine; the guest binding lacks it.)
    test-agenix-verbatim-blocks = denTest (
      { den, igloo, ... }:
      let
        agenixLike =
          { host, ... }:
          {
            nixos.age.hostPubkey = builtins.readFile host.public_key;
          };
      in
      {
        imports = [ (parentBase den) ];
        den.hosts.x86_64-linux.igloo = {
          public_key = ./delivered-child-host.nix;
          deliveredChildren.guest = mkGuest den { }; # NO public_key.
        };
        den.schema.host.includes = [ agenixLike ];
        den.aspects.guest-aspect.nixos.networking.hostName = "guest-vm";

        expr = igloo.microvm.vms.guest.config.age.hostPubkey;
        expectedError = {
          type = "EvalError";
          msg = "public_key";
        };
      }
    );

    # REALISTIC GUEST: real users + agenix (host pubkey + per-user secret) +
    # the stateVersion default. Exercises the COMPLETE tailoring surface
    # through the primitive. A delivered child built as a raw entity bypasses
    # userType, so the user is a FULL record (gap G6).
    test-realistic-guest = denTest (
      { den, igloo, ... }:
      let
        agenixBattery =
          { host, ... }:
          {
            nixos.age.hostPubkey = builtins.readFile host.public_key;
            nixos.age.secrets."tux-password".file = host.public_key;
          };
      in
      {
        imports = [ (parentBase den) ];
        den.deliveredChild.stateVersion = "25.11";

        den.hosts.x86_64-linux.igloo = {
          public_key = ./delivered-child-host.nix;
          deliveredChildren.guest = mkGuest den {
            public_key = ./delivered-child-host.nix;
            # tux is a homeManager user → HM synthesis now fires; pin the stub
            # module (the real module needs guest re-instantiation).
            home-manager = {
              enable = true;
              module = hmStub;
            };
            users.tux = {
              name = "tux";
              userName = "tux";
              classes = [ "homeManager" ];
            };
          };
        };
        den.schema.host.includes = [ agenixBattery ];
        den.aspects.guest-aspect.nixos.networking.hostName = "guest-vm";

        expr = {
          pubkeyResolved = igloo.microvm.vms.guest.config.age.hostPubkey != "";
          secretPresent = igloo.microvm.vms.guest.config.age.secrets ? "tux-password";
          hn = igloo.microvm.vms.guest.config.networking.hostName;
          stateVersion = igloo.microvm.vms.guest.config.system.stateVersion;
        };
        expected = {
          pubkeyResolved = true;
          secretPresent = true;
          hn = "guest-vm";
          stateVersion = "25.11";
        };
      }
    );

    # HOME-MANAGER SYNTHESIS: a guest user with classes = ["homeManager"] and a
    # homeManager aspect must produce a home-manager OUTPUT in the delivered
    # config — i.e. igloo.microvm.vms.guest.config.home-manager.users.tux.<v>.
    #
    # This exercises the guest-hm-user-forward bridge: the standard battery's
    # per-user forward appends at the user-under-guest scope (below the isolated
    # guest), which isolation drops from the parent. The bridge resolves each
    # homeManager user's homeManager content at the GUEST scope (the delivery
    # route's collection root) and delivers it under nixos
    # home-manager.users.<u>. WITHOUT it the delivered config has NO
    # home-manager.users.tux and this test FAILS.
    #
    # The delivered content is a `{ imports = [...]; }` home-manager module — the
    # exact shape the guest's real home-manager module evaluates when the microvm
    # re-instantiates the guest config downstream. These unit tests never
    # re-instantiate (the guest's nixos content lands in the freeform microvm
    # slot), so the assertion re-evaluates the delivered imports to observe the
    # actual home-manager output. nix-config exercises the real module on
    # instantiation.
    test-home-synthesis = denTest (
      {
        den,
        lib,
        igloo,
        ...
      }:
      {
        imports = [ (parentBase den) ];
        den.deliveredChild.stateVersion = "25.11";

        den.hosts.x86_64-linux.igloo.deliveredChildren.guest = mkGuest den {
          # Consumer override: pin a stub HM module so the host-submodule
          # home-manager.enable option exists (detection) without pulling the
          # real home-manager module (which only evaluates on re-instantiation).
          home-manager = {
            enable = true;
            module = hmStub;
          };
          users.tux = {
            name = "tux";
            userName = "tux";
            classes = [ "homeManager" ];
            # The guest user's home config, attached inline as the aspect.
            aspect.homeManager.programs.git.enable = true;
          };
        };
        den.aspects.guest-aspect.nixos.networking.hostName = "guest-vm";

        # The delivered config carries the per-user home-manager content as a
        # `{ imports = [...]; }` module under home-manager.users.tux — the exact
        # shape the guest's real home-manager module evaluates when the microvm
        # re-instantiates the delivered config. We re-evaluate those imports
        # here (with a permissive freeform module set, the way the microvm
        # nixosSystem would) and assert the user's program setting lands.
        expr = {
          hmUsers = builtins.attrNames igloo.microvm.vms.guest.config.home-manager.users;
          gitEnabled =
            (lib.evalModules {
              modules = [
                { config._module.freeformType = lib.types.lazyAttrsOf lib.types.anything; }
              ]
              ++ igloo.microvm.vms.guest.config.home-manager.users.tux.imports;
            }).config.programs.git.enable;
        };
        expected = {
          hmUsers = [ "tux" ];
          gitEnabled = true;
        };
      }
    );

    # THE cortex repro: a guest-only option must not leak onto the parent's
    # toplevel (microvm.guest does not exist there) and must arrive at the
    # delivery path.
    test-no-guest-option-leak = denTest (
      { den, igloo, ... }:
      {
        imports = [ (parentBase den) ];
        den.hosts.x86_64-linux.igloo.deliveredChildren.guest = mkGuest den { };
        den.aspects.guest-aspect.nixos = {
          networking.hostName = "guest-vm";
          microvm.guest.enable = true;
        };

        # Forcing the parent's toplevel would throw 'option microvm.guest does
        # not exist' if the guest's nixos leaked. networking.hostName is unset
        # on the parent, so it falls back to the nixos default.
        expr = {
          parentEvals = igloo.networking.hostName;
          delivered = igloo.microvm.vms.guest.config.microvm.guest.enable;
        };
        expected = {
          parentEvals = "nixos";
          delivered = true;
        };
      }
    );

    # THE load-bearing regression: compose entities are NOT isolated — a
    # home-manager user on the PARENT still lands in the parent's nixos even
    # while a delivered child coexists. We use the real home-manager battery
    # (parent igloo is a genuine nixosSystem) and observe the parent user's HM
    # content via the tuxHm fixture (igloo.home-manager.users.tux).
    test-parent-home-manager-intact = denTest (
      {
        den,
        tuxHm,
        igloo,
        ...
      }:
      {
        imports = [ (parentBase den) ];
        den.hosts.x86_64-linux.igloo = {
          users.tux = { };
          deliveredChildren.guest = mkGuest den { };
        };
        # Parent user's home-manager content (standard battery + real module),
        # authored on the user's own aspect (named after the user).
        den.aspects.tux.homeManager.programs.git.enable = true;
        den.aspects.guest-aspect.nixos.networking.hostName = "guest-vm";

        expr = {
          parentHm = tuxHm.programs.git.enable;
          delivered = igloo.microvm.vms.guest.config.networking.hostName;
        };
        expected = {
          parentHm = true;
          delivered = "guest-vm";
        };
      }
    );

    # Reused fleet aspect: a SHARED nixos-authored aspect composed into the
    # guest lands at the delivery path and does NOT leak to the parent.
    test-reused-nixos-aspect-delivered = denTest (
      {
        den,
        lib,
        igloo,
        ...
      }:
      {
        imports = [ (parentBase den) ];
        den.hosts.x86_64-linux.igloo.deliveredChildren.guest = mkGuest den { };
        den.aspects.shared-role.nixos.boot.kernelModules = [ "shared-role-module" ];
        den.aspects.guest-aspect = {
          includes = [ den.aspects.shared-role ];
          nixos.networking.hostName = "guest-vm";
        };

        expr = {
          delivered = lib.elem "shared-role-module" igloo.microvm.vms.guest.config.boot.kernelModules;
          parent = lib.elem "shared-role-module" igloo.boot.kernelModules;
        };
        expected = {
          delivered = true;
          parent = false;
        };
      }
    );

  };
}
