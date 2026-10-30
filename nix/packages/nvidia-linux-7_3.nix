# Nixpkgs' production 595 point release includes NVIDIA's Linux 7.3 fixes.
# Reuse the machine's own mkDriver recipe and dependencies, with matching
# userspace, settings, persistence daemon and kernel sources. Remove this pin
# when stable Nixpkgs supplies this version or newer.
# Source: https://github.com/NixOS/nixpkgs/blob/31ecbaca1bdefa45dffc409f0250bd8039ea0010/pkgs/os-specific/linux/nvidia-x11/default.nix
{
  version = "595.112.07";
  sha256_64bit = "sha256-Gjjs1Tii2mIypzMBhAY69Z6fyUbJCMylVb0HkJhIufA=";
  sha256_aarch64 = "sha256-7qQuOKX9xS/wpKa+bEOqsS2euJjJu182vl+6UU6bxR0=";
  openSha256 = "sha256-nQnXGCcvo4i7eGaVft3Xc9dRUPPH0v9Zi87cfI4i/Ys=";
  settingsSha256 = "sha256-2bWSou/9J3EojhSRXBol/+yGGu2XZ6EuCptb5qXHM14=";
  persistencedSha256 = "sha256-cGMEUXN7WPu822zZDLTSu6Owj8VXG4PNmhe9oKqMMKI=";
}
