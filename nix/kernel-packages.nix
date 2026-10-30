# Keep the installer and installed OS on Nixpkgs' latest stable kernel.
# ZFS 2.4.4 predates Linux 7.3. Backport OpenZFS's reviewed API fixes and
# compatibility declaration without changing its userspace or pool features.
# Drop the backport when the machine's Nixpkgs supplies compatible ZFS.
{ pkgs }:
let
  nvidia = import ./packages/nvidia-linux-7_3.nix;
in pkgs.linuxPackages_latest.extend (_final: previous: {
  zfs_2_4 = if previous.zfs_2_4.version == "2.4.4"
    && pkgs.lib.versions.majorMinor previous.kernel.version == "7.3"
    && previous.zfs_2_4.meta.broken
    then pkgs.callPackage ./packages/zfs-linux-7_3.nix {
      package = previous.zfs_2_4;
    } else previous.zfs_2_4;
  nvidiaPackages = previous.nvidiaPackages // pkgs.lib.genAttrs
    [ "stable" "production" "latest" "bleeding_edge" ]
    (name: let package = previous.nvidiaPackages.${name}; in
      if pkgs.lib.versions.majorMinor previous.kernel.version == "7.3"
        && pkgs.lib.versions.major package.version == "595"
        && pkgs.lib.versionOlder package.version nvidia.version
      then previous.nvidiaPackages.mkDriver nvidia
      else package);
})
