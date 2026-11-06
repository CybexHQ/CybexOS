# Audited equivalents of selected nixos-hardware settings, with provenance and
# removal conditions in the shared catalogue. Deliberately no upstream module
# import: their transitive defaults can select kernels and power managers.
{ config, lib, pkgs, ... }:
let
  cfg = config.cybexos;
  hardware = cfg.hardware;
  catalogue = builtins.fromJSON (builtins.readFile ../../lifecycle/cybexos/hardware-profiles.json);
  approved = builtins.filter (profile: profile.approved) catalogue.profiles;
  ids = map (profile: profile.id) approved;
  selected = lib.findFirst (profile: profile.id == hardware.profile) null approved;
  active = cfg.enable && selected != null;
  framework = hardware.profile == "framework-13-amd-7040";
  thinkpad = hardware.profile == "lenovo-thinkpad-t14-gen5-amd";
  kernel = config.boot.kernelPackages.kernel.version;
in {
  options.cybexos.hardware = {
    profile = lib.mkOption {
      type = lib.types.nullOr (lib.types.enum ids);
      default = null;
      description = ''
        Approved exact model profile, normally selected by the fresh installer's
        read-only DMI matcher. Inclusion means experimental configuration
        support, never physical qualification. Existing xps/zbook settings
        remain independent; selecting their metadata does not enable them.
      '';
    };
    framework13Amd7040 = {
      disablePsr = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Disable AMD panel self-refresh on the exact Framework 13 AMD 7040
          profile, following nixos-hardware's hang workaround. Costs idle
          power. Set false when supplying a personal amdgpu.dcdebugmask or
          testing a fixed kernel; no fixed upstream version is established.
        '';
      };
      ethernetAutosuspend = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Use nixos-hardware's 20-second USB 0bda:8156 Ethernet expansion-card autosuspend delay on this exact profile";
      };
    };
    thinkpadT14Gen5Amd.preventEcWakeup = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Disable embedded-controller wake on the T14 Gen 5 AMD (21MC/21MD)
        profile to avoid reported s2idle battery drain. Wake behavior needs
        physical checking on the exact BIOS. Set false to retain EC wake.
      '';
    };
  };
  config = lib.mkMerge [
    (lib.mkIf (cfg.enable || cfg.installationMedium) {
      # A different path from hardware.nix's existing hardware-profile.json.
      # Carry every approved identity and source on the generic live medium.
      environment.etc."cybexos/hardware-support.json".text = builtins.toJSON (catalogue // {
        selectedProfile = hardware.profile;
        selected = selected;
        configuredKernel = kernel;
        installationMedium = cfg.installationMedium;
      });
    })
    (lib.mkIf active {
      assertions = [
        {
          assertion = pkgs.stdenv.hostPlatform.system == "x86_64-linux";
          message = "Cybex OS hardware profiles support only Intel/AMD x86_64 UEFI PCs.";
        }
        {
          assertion = lib.versionAtLeast kernel selected.kernel.minimum
            && (selected.kernel.maximumExclusive == null
              || lib.versionOlder kernel selected.kernel.maximumExclusive);
          message = "The selected hardware profile is outside its reviewed stock-kernel range.";
        }
      ];
    })
    (lib.mkIf (active && framework && hardware.framework13Amd7040.disablePsr) {
      # nixos-hardware framework/13-inch/common/amd.nix, disablePsr bit 16.
      # No kernel change or patch; the explicit option permits personal masks.
      boot.kernelParams = [ "amdgpu.dcdebugmask=0x10" ];
    })
    (lib.mkIf (active && framework && hardware.framework13Amd7040.ethernetAutosuspend) {
      # nixos-hardware framework/13-inch/common/default.nix. Check the exact
      # expansion-card USB IDs as well as the selected model; no global rule.
      services.udev.extraRules = ''
        ACTION=="add", SUBSYSTEM=="usb", ATTR{idVendor}=="0bda", ATTR{idProduct}=="8156", ATTR{power/autosuspend}="20"
      '';
    })
    (lib.mkIf (active && thinkpad && hardware.thinkpadT14Gen5Amd.preventEcWakeup) {
      # nixos-hardware lenovo/thinkpad/t14/amd/gen5/default.nix.
      boot.kernelParams = [ "acpi.ec_no_wakeup=1" ];
    })
  ];
}
