# Small, standalone evaluation/build check, without building a kernel/system.
# nix build --impure --no-link --expr 'import ./nix/tests/hardware-profiles.nix {
#   nixpkgs = (builtins.getFlake (toString ./.)).inputs.nixpkgs;
# }'
{ nixpkgs, system ? "x86_64-linux" }:
let
  inherit (nixpkgs) lib;
  pkgs = nixpkgs.legacyPackages.${system};
  catalogue = builtins.fromJSON (builtins.readFile ../../lifecycle/cybexos/hardware-profiles.json);
  evaluate = settings: (lib.nixosSystem {
    inherit system;
    modules = [
      ../modules/hardware-profiles.nix
      ({ lib, pkgs, ... }: {
        options.cybexos = {
          enable = lib.mkEnableOption "profile evaluation";
          installationMedium = lib.mkEnableOption "profile medium evaluation";
        };
        config = {
          cybexos.enable = lib.mkDefault true;
          boot.kernelPackages = lib.mkDefault pkgs.linuxPackages_latest;
          boot.loader.systemd-boot.enable = true;
          services.power-profiles-daemon.enable = true;
          services.tlp.enable = false;
          services.tuned.enable = false;
          fileSystems."/" = { device = "/dev/test-root"; fsType = "ext4"; };
          fileSystems."/boot" = { device = "/dev/test-boot"; fsType = "vfat"; };
          system.stateVersion = "26.05";
        };
      })
      settings
    ];
  }).config;
  generic = evaluate {};
  framework = evaluate { cybexos.hardware.profile = "framework-13-amd-7040"; };
  thinkpad = evaluate { cybexos.hardware.profile = "lenovo-thinkpad-t14-gen5-amd"; };
  custom = evaluate {
    cybexos.hardware = {
      profile = "framework-13-amd-7040";
      framework13Amd7040 = { disablePsr = false; ethernetAutosuspend = false; };
    };
    boot.kernelParams = [ "amdgpu.dcdebugmask=0x400" "personal=retained" ];
  };
  ecWake = evaluate {
    cybexos.hardware.profile = "lenovo-thinkpad-t14-gen5-amd";
    cybexos.hardware.thinkpadT14Gen5Amd.preventEcWakeup = false;
  };
  medium = evaluate {
    cybexos.enable = false;
    cybexos.installationMedium = true;
  };
  disabled = evaluate {
    cybexos.enable = false;
    cybexos.hardware.profile = "framework-13-amd-7040";
  };
  metadata = c: builtins.fromJSON c.environment.etc."cybexos/hardware-support.json".text;
  cases = map (p: evaluate { cybexos.hardware.profile = p.id; }) catalogue.profiles;
  invariant = c:
    c.boot.kernelPackages.kernel.drvPath == generic.boot.kernelPackages.kernel.drvPath
    && c.boot.kernelPatches == generic.boot.kernelPatches
    && c.boot.extraModulePackages == generic.boot.extraModulePackages
    && c.nixpkgs.overlays == generic.nixpkgs.overlays
    && c.services.power-profiles-daemon.enable
    && !c.services.tlp.enable && !c.services.tuned.enable
    && c.boot.loader.systemd-boot.enable == generic.boot.loader.systemd-boot.enable
    && c.boot.loader.grub.enable == generic.boot.loader.grub.enable;
  validAssertions = c: lib.all (a: a.assertion) c.assertions;
  failed = evaluate {
    cybexos.hardware.profile = "dell-xps-14-da14260";
    # Evaluate an older stock package set only; no kernel is built.
    boot.kernelPackages = lib.mkForce pkgs.linuxPackages_6_12;
  };
  invalid = builtins.tryEval (evaluate {
    cybexos.hardware.profile = "unknown-near-match";
  }).cybexos.hardware.profile;
in
assert lib.all invariant cases;
assert lib.all validAssertions cases;
assert !validAssertions failed;
assert !invalid.success;
assert lib.elem "amdgpu.dcdebugmask=0x10" framework.boot.kernelParams;
assert !(lib.elem "amdgpu.dcdebugmask=0x10" generic.boot.kernelParams);
assert !(lib.elem "acpi.ec_no_wakeup=1" generic.boot.kernelParams);
assert lib.elem "acpi.ec_no_wakeup=1" thinkpad.boot.kernelParams;
assert !(lib.elem "acpi.ec_no_wakeup=1" ecWake.boot.kernelParams);
assert !(lib.elem "amdgpu.dcdebugmask=0x10" custom.boot.kernelParams);
assert lib.elem "amdgpu.dcdebugmask=0x400" custom.boot.kernelParams;
assert lib.elem "personal=retained" custom.boot.kernelParams;
assert lib.hasInfix ''ATTR{idVendor}=="0bda", ATTR{idProduct}=="8156"'' framework.services.udev.extraRules;
assert !(lib.hasInfix "power/autosuspend" custom.services.udev.extraRules);
assert !(lib.hasInfix "power/autosuspend" generic.services.udev.extraRules);
assert !(lib.elem "amdgpu.dcdebugmask=0x10" disabled.boot.kernelParams);
assert (metadata medium).selectedProfile == null;
assert (metadata framework).selected.id == "framework-13-amd-7040";
assert (metadata generic).profiles == catalogue.profiles;
assert !(generic.environment.etc ? "cybexos/hardware-profile.json");
pkgs.writeText "cybexos-hardware-profiles-evaluation" (builtins.toJSON {
  schema = 1;
  profiles = map (p: p.id) catalogue.profiles;
  kernel = generic.boot.kernelPackages.kernel.version;
  status = "configuration-tested; physical qualification not run";
})
