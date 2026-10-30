# Keep the installer and installed OS on Nixpkgs' latest kernel series
# (linuxPackages_latest), with its own NVIDIA drivers.
# ZFS 2.4.4 predates Linux 7.3. Backport OpenZFS's reviewed API fixes and
# compatibility declaration without changing its userspace or pool features.
# Drop the backport when the machine's Nixpkgs supplies compatible ZFS.
# The kernel set's own callPackage supplies kernelModuleMakeFlags, as for
# Nixpkgs' zfs_2_4: kbuild then signs the modules and writes the .ko.cer
# certificates NixOS's module aggregation requires.
{ pkgs }:
pkgs.linuxPackages_latest.extend (final: previous: {
  zfs_2_4 = if previous.zfs_2_4.version == "2.4.4"
    && pkgs.lib.versions.majorMinor previous.kernel.version == "7.3"
    && previous.zfs_2_4.meta.broken
    then final.callPackage ./packages/zfs-linux-7_3.nix {
      package = previous.zfs_2_4;
    } else previous.zfs_2_4;
})
