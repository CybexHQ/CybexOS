# Builds this computer performs by design. Everything else in the system must
# come prebuilt from the configured caches (cache.nixos.org by default): the
# staged updater checks a candidate's build plan and holds back a NixOS
# package update until NixOS has finished building it (lifecycle/cybexos/
# prebuilt.py). Cybex OS's own packages, unfree vendor downloads (never cached
# by NixOS) and out-of-tree kernel modules are expected local builds.
{ config, lib, ... }:
let
  cfg = config.cybexos;
  source = toString ../.. + "/";
  unfree = package: !(lib.all (license: license.free or true) (lib.toList (package.meta.license or [])));
  ours = package: lib.hasPrefix source (package.meta.position or "")
    || lib.hasPrefix "cybexos-" (package.pname or package.name or "");
  candidates = config.environment.systemPackages ++ config.fonts.packages
    ++ config.boot.plymouth.themePackages ++ config.networking.networkmanager.plugins
    ++ lib.toList config.hardware.firmware ++ config.services.udev.packages ++ config.systemd.packages;
  expected = builtins.filter (package: lib.isDerivation package && (unfree package || ours package)) candidates
    ++ config.boot.extraModulePackages
    ++ lib.optional (lib.elem "nvidia" config.services.xserver.videoDrivers) config.hardware.nvidia.package
    ++ cfg.updates.expectedBuilds;
in {
  options.cybexos.updates.expectedBuilds = lib.mkOption {
    type = lib.types.listOf lib.types.package;
    default = [ ];
    description = ''
      Packages this computer may build itself during updates, in addition to
      Cybex OS's own packages, unfree vendor downloads and kernel modules.
      Add personal packages that you deliberately build from source.
    '';
  };
  config = lib.mkIf cfg.enable {
    system.build.cybexosExpectedBuilds = lib.unique
      (map (package: builtins.unsafeDiscardStringContext package.drvPath) expected);
  };
}
