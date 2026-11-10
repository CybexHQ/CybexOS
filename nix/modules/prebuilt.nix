# Builds this computer performs by design. Everything else in the system must
# come prebuilt from the configured caches (cache.nixos.org by default): the
# staged updater checks a candidate's build plan and holds back a NixOS
# package update until NixOS has finished building it (lifecycle/cybexos/
# prebuilt.py). Cybex OS's own packages, unfree vendor downloads (never cached
# by NixOS) and out-of-tree kernel modules are expected local builds. A vendor
# download's own inputs are ordinary Nixpkgs packages, which NixOS does build:
# those must still come prebuilt (cybexosVendorBuilds).
{ config, lib, pkgs, ... }:
let
  cfg = config.cybexos;
  kernel = config.boot.kernelPackages.kernel;
  # Compare against this machine's selected Nixpkgs source without personal
  # overlays. Extending the external-module set (kernel-packages.nix) leaves
  # this identity intact; kernel patches/config overrides do not.
  stockKernel = (import pkgs.path {
    inherit (pkgs.stdenv.hostPlatform) system;
    config = { };
    overlays = [ ];
  }).linuxPackages_latest.kernel;
  source = toString ../.. + "/";
  unfree = package: !(lib.all (license: license.free or true) (lib.toList (package.meta.license or [])));
  ours = package: lib.hasPrefix source (package.meta.position or "")
    || lib.hasPrefix "cybexos-" (package.pname or package.name or "");
  candidates = config.environment.systemPackages ++ config.fonts.packages
    ++ config.boot.plymouth.themePackages ++ config.networking.networkmanager.plugins
    ++ lib.toList config.hardware.firmware ++ config.services.udev.packages ++ config.systemd.packages;
  drivers = config.boot.extraModulePackages
    ++ lib.optional (lib.elem "nvidia" config.services.xserver.videoDrivers) config.hardware.nvidia.package;
  expected = builtins.filter (package: lib.isDerivation package && (unfree package || ours package)) candidates
    ++ drivers ++ cfg.updates.expectedBuilds;
  # The unfree vendor downloads among them. They build here, but their inputs
  # are ordinary Nixpkgs packages that must come prebuilt: on 2026-11-10 the
  # channel's ChatGPT needed a codex and a tectonic NixOS had failed to build.
  vendor = builtins.filter (package: lib.isDerivation package && unfree package && !(ours package)
      && !(lib.elem package.drvPath (map (driver: driver.drvPath) drivers)))
    (candidates ++ cfg.updates.expectedBuilds);
  paths = packages: lib.unique
    (map (package: builtins.unsafeDiscardStringContext package.drvPath)
      (builtins.filter (package: package.drvPath != kernel.drvPath) packages));
in {
  options.cybexos.updates.expectedBuilds = lib.mkOption {
    type = lib.types.listOf lib.types.package;
    default = [ ];
    description = ''
      Packages this computer may build itself during updates, in addition to
      Cybex OS's own packages, unfree vendor downloads and kernel modules.
      Add personal packages that you deliberately build from source.
      This never exempts the Linux kernel from the prebuilt requirement.
    '';
  };
  config = lib.mkIf (cfg.enable || cfg.installationMedium) {
    assertions = [ {
      assertion = kernel.drvPath == stockKernel.drvPath;
      message = "Cybex OS requires the unmodified selected Nixpkgs linuxPackages_latest kernel. Kernel patches, custom configuration and package overlays are unsupported; no kernel compilation was started. Personal declarations were not changed.";
    } ];
    system.build.cybexosExpectedBuilds = paths expected;
    system.build.cybexosVendorBuilds = paths vendor;
  };
}
