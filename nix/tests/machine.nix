{ lib, ... }: {
  cybexos = { enable = true; primaryUser = "tester"; features = { proprietary = false; steam = false; docker = false; }; };
  fileSystems."/" = { device = "/dev/vda2"; fsType = "ext4"; };
  fileSystems."/boot" = { device = "/dev/vda1"; fsType = "vfat"; };
  boot.loader.efi.canTouchEfiVariables = lib.mkForce false;
  # Every system has all glibc locales (nix/modules/default.nix), so the
  # lifecycle VM can stage a system language change: the prebuilt candidate
  # already holds the locale, and a new default only rewrites /etc.
  system.stateVersion = "26.05";
}
