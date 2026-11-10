# Cybex OS's own packages that are not installed by default: Software offers
# them by these attribute names beside Nixpkgs' (cybexos.software.packages).
# Like unfree vendor apps, they unpack their maker's download on the computer
# (nix/modules/prebuilt.nix).
{ pkgs }: {
  # Brave Origin, an install in Software's browser picker.
  brave-origin = pkgs.callPackage ./brave { };
}
