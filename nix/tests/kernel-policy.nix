# Evaluation only: exact recipe identity is stronger than equal version text.
# No kernel, external module, ISO or VM is built by this check.
{ nixpkgs, pkgs, module, system, installer, approvedProfiles ? [ ] }:
let
  lib = nixpkgs.lib;
  stock = pkgs.linuxPackages_latest.kernel.drvPath;
  machine = hardware: extra: (lib.nixosSystem {
    inherit system;
    modules = [ module ./machine.nix { cybexos.hardware = hardware; } extra ];
  }).config;
  generic = machine { } { };
  xps = sku: machine { xps = { enable = true; inherit sku; camera = false; }; } { };
  zbook = machine { zbookUltraG1a.enable = true; } { };
  # Test every catalogue-approved profile as well as the generic system.
  # The production assertion applies regardless of model recognition.
  profiles = map (profile: machine { inherit profile; } { }) approvedProfiles;
  nvidia = open: machine { nvidia = true; nvidiaOpen = open; } { };
  stockSystems = [ generic installer installer.cybexos.installer.payload.config
    zbook (nvidia true) (nvidia false) ] ++ map xps [ "0DB9" "0DBA" "0E53" "0E54" ] ++ profiles;
  matched = extra: machine { xps = { enable = true; sku = "0DB9"; }; } extra;
  customConfig = matched {
    boot.kernelPatches = [ {
      name = "policy-config-fixture";
      patch = null;
      structuredExtraConfig.LOCALVERSION = lib.mkForce (lib.kernel.freeform "-policy-test");
    } ];
  };
  patched = matched {
    boot.kernelPatches = [ {
      name = "policy-patch-fixture";
      patch = pkgs.writeText "kernel-policy-fixture.patch" "fixture, never built\n";
    } ];
  };
  overlaid = matched {
    nixpkgs.overlays = [ (final: previous: {
      linuxPackages_latest = previous.linuxPackages_latest.extend (finalKernel: previousKernel: {
        kernel = previousKernel.kernel.overrideAttrs (old: { postPatch = (old.postPatch or "") + "\n# policy fixture\n"; });
      });
    }) ];
  };
  refused = c: lib.any (a:
    lib.hasPrefix "Cybex OS requires the unmodified" a.message && !a.assertion) c.assertions;
  # Personal declarations retain precedence; they are never rewritten to
  # manufacture a passing profile. Unsupported choices receive an assertion.
  personal = machine { } { boot.kernelPackages = pkgs.linuxPackages; };
  genericPatched = machine { } {
    boot.kernelPatches = [ {
      name = "generic-policy-fixture";
      patch = null;
      structuredExtraConfig.LOCALVERSION = lib.mkForce (lib.kernel.freeform "-policy-test");
    } ];
  };
  kernelExpected = machine { } ({ config, ... }: {
    cybexos.updates.expectedBuilds = [ config.boot.kernelPackages.kernel pkgs.hello ];
  });
in
assert lib.all (c: c.boot.kernelPackages.kernel.drvPath == stock) stockSystems;
assert lib.all refused [ customConfig patched overlaid (matched { boot.kernelPackages = pkgs.linuxPackages; }) ];
assert personal.boot.kernelPackages.kernel.drvPath == pkgs.linuxPackages.kernel.drvPath;
assert refused personal && refused genericPatched;
assert !(builtins.elem stock kernelExpected.system.build.cybexosExpectedBuilds);
assert builtins.elem pkgs.hello.drvPath kernelExpected.system.build.cybexosExpectedBuilds;
# ZFS's external-module extension must preserve the kernel itself.
assert (import ../kernel-packages.nix { inherit pkgs; }).kernel.drvPath == stock;
pkgs.writeText "cybexos-stock-kernel-policy" (builtins.toJSON {
  kernel = builtins.unsafeDiscardStringContext stock;
  configurations = builtins.length stockSystems;
  inherit approvedProfiles;
})
