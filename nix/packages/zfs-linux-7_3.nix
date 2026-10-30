# OpenZFS #19082 and #19553, applied to the released 2.4.4 kernel package.
# Use Nixpkgs' own recipe and compatibility check; do not permit broken modules
# or unsupported kernels. The patches retain support for older kernel APIs.
{ package, callPackage }:
package.override {
  callPackage = path: args: settings: callPackage path args (settings // {
    kernelMaxSupportedMajorMinor = "7.3";
    extraPatches = (settings.extraPatches or []) ++ [
      ../patches/zfs-linux-7_3-cpu-features.patch
      ../patches/zfs-linux-7_3-inode-create.patch
      ../patches/zfs-linux-7_3-bvec-offset.patch
      ../patches/zfs-linux-7_3-kthread-filesystem.patch
      ../patches/zfs-linux-7_3-meta.patch
    ];
  });
}
