# Only device metadata enters the ISO, not NVIDIA's vendor driver or installer.
# Sources and versions follow the selected Nixpkgs kernel set automatically.
{ runCommand, python3, zstd, nvidiaPackages }:
runCommand "cybexos-hardware-drivers.json" {
  nativeBuildInputs = [ python3 zstd ];
} ''
  python3 ${../../scripts/nvidia-hardware-catalogue.py} \
    --open-source ${nvidiaPackages.stable.src} --open-version ${nvidiaPackages.stable.version} \
    --closed-source ${nvidiaPackages.legacy_580.src} --closed-version ${nvidiaPackages.legacy_580.version} \
    --output "$out"
''
