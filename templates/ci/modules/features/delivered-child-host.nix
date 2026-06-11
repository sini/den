# Acceptance tests for the delivered-child-host PRIMITIVE
# (modules/policies/delivered-child-host.nix).
#
# A delivered child is a guest host that resolves as a nested child scope under
# its parent host and is realized INTO the parent's config
# (microvm.vms.<name>.config) instead of producing a standalone
# nixosConfigurations.<name> output.
#
# HARNESS NOTE: denTest only exposes INSTANTIATED hosts
# (config.flake.nixosConfigurations.<name>.config). A delivered child has NO
# denTest handle, so EVERY assertion observes the child THROUGH the parent's
# instantiated output (`igloo`), reading a child-sourced value back out of
# `igloo.microvm.vms.<name>.config.*`.
#
# The primitive supplies: a parent option (host.deliveredChildren), a dedicated
# `delivered-guest` kind whose includes are a curated subset of
# den.schema.host.includes, the delivery policy (resolve + class-isolation +
# route+collectSubtree), and an expose policy. Tests use the primitive — they
# declare children via den.hosts.<sys>.igloo.deliveredChildren rather than
# hand-rolling the resolve/route pair.
{ denTest, lib, ... }:
let
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

  # Common parent wiring: the microvm slot on igloo. Returned as a module so it
  # merges (NOT `//`, which would clobber the test body's own `den` attr).
  parentBase = den: {
    den.aspects.igloo.includes = [ den.aspects.microvm-slot ];
    den.aspects.microvm-slot.nixos.imports = [ microvmSlot ];
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
        den.aspects.guest-aspect.guest-os.networking.hostName = "guest-vm";

        expr = igloo.microvm.vms.guest.config.networking.hostName;
        expected = "guest-vm";
      }
    );

    # PARTICIPATION: a curated host-include value fires in the CHILD scope and
    # arrives in the delivered config. The host-include emits into guest-os.
    test-participation = denTest (
      { den, igloo, ... }:
      {
        imports = [ (parentBase den) ];
        den.hosts.x86_64-linux.igloo.deliveredChildren.guest = mkGuest den { };
        den.schema.host.includes = [
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

    # NO STANDALONE OUTPUT: the primitive gives the guest intoAttr = [] and no
    # policy.instantiate, so nixosConfigurations.guest does NOT exist; only the
    # parent is instantiated.
    test-no-standalone-output = denTest (
      { den, config, ... }:
      {
        imports = [ (parentBase den) ];
        den.hosts.x86_64-linux.igloo.deliveredChildren.guest = mkGuest den { };
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

    # AGENIX DOESN'T THROW (retarget + parent key): an agenix-like host-include
    # reads host.public_key via builtins.readFile. The guest sets public_key to
    # the parent's existing key path (clean override), so it resolves and the
    # value lands in the delivered config through the parent.
    test-agenix-tailored = denTest (
      { den, igloo, ... }:
      let
        agenixLike =
          { host, ... }:
          {
            guest-os.age.hostPubkey = builtins.readFile host.public_key;
          };
      in
      {
        imports = [ (parentBase den) ];
        den.hosts.x86_64-linux.igloo = {
          public_key = ./delivered-child-host.nix;
          deliveredChildren.guest = mkGuest den { public_key = ./delivered-child-host.nix; };
        };
        den.schema.host.includes = [ agenixLike ];
        den.aspects.guest-aspect.guest-os.networking.hostName = "guest-vm";

        expr =
          igloo.microvm.vms.guest.config.age.hostPubkey != ""
          && igloo.microvm.vms.guest.config.networking.hostName == "guest-vm";
        expected = true;
      }
    );

    # NEGATIVE (why tailoring is required): a verbatim guest WITHOUT public_key
    # hard-blocks the agenix-like readFile the moment the delivered value is
    # forced through the parent.
    test-agenix-verbatim-blocks = denTest (
      { den, igloo, ... }:
      let
        agenixLike =
          { host, ... }:
          {
            guest-os.age.hostPubkey = builtins.readFile host.public_key;
          };
      in
      {
        imports = [ (parentBase den) ];
        den.hosts.x86_64-linux.igloo = {
          public_key = ./delivered-child-host.nix;
          deliveredChildren.guest = mkGuest den { }; # NO public_key.
        };
        den.schema.host.includes = [ agenixLike ];
        den.aspects.guest-aspect.guest-os.networking.hostName = "guest-vm";

        expr = igloo.microvm.vms.guest.config.age.hostPubkey;
        expectedError = {
          type = "EvalError";
          msg = "public_key";
        };
      }
    );

    # REALISTIC GUEST: real users + agenix (host pubkey + per-user secret) +
    # the guest-os stateVersion default. Exercises the COMPLETE tailoring
    # surface through the primitive. A delivered child built as a raw entity
    # bypasses userType, so the user is a FULL record (gap G6).
    test-realistic-guest = denTest (
      { den, igloo, ... }:
      let
        agenixBattery =
          { host, ... }:
          {
            guest-os.age.hostPubkey = builtins.readFile host.public_key;
            guest-os.age.secrets."tux-password".file = host.public_key;
          };
      in
      {
        imports = [ (parentBase den) ];
        den.deliveredChild.stateVersion = "25.11";

        den.hosts.x86_64-linux.igloo = {
          public_key = ./delivered-child-host.nix;
          deliveredChildren.guest = mkGuest den {
            public_key = ./delivered-child-host.nix;
            users.tux = {
              name = "tux";
              userName = "tux";
              classes = [ "homeManager" ];
            };
          };
        };
        den.schema.host.includes = [ agenixBattery ];
        den.aspects.guest-aspect.guest-os.networking.hostName = "guest-vm";

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

  };
}
