# A representative fresh installation, evaluated only so the installation ISO
# can carry its store paths: the default application groups minus the unfree
# ones, which the medium cannot redistribute. It never boots. Installation
# builds the real machine from its own configuration and copies whatever it
# shares with this system from the medium instead of downloading it.
#
# The default software profiles (desktop/software/catalogue.json, today
# Software Development) are on the medium too, so the recommended choice in
# the installer's Software step needs no download. Only their free apps: the
# unfree ones download from their vendors during installation, like the other
# profiles. The installer shows the default profiles as on this USB stick.
{ lib, ... }:
let
  catalogue = lib.importJSON ../../desktop/software/catalogue.json;
  apps = lib.listToAttrs (map (app: lib.nameValuePair app.id app) catalogue.apps);
  defaults = builtins.filter (profile: profile.default or false) catalogue.profiles;
  free = builtins.filter (app: app.free) (map (id: apps.${id}) (lib.unique (lib.concatMap (profile: profile.apps) defaults)));
in {
  cybexos = {
    enable = true;
    encrypted = true;
    features = { proprietary = false; steam = false; };
    software.packages = map (app: app.attribute) free;
  };
  fileSystems."/" = { device = "/dev/mapper/cybexos-install-root"; fsType = "ext4"; };
  fileSystems."/boot" = { device = "/dev/disk/by-label/CYBEXOS_EFI"; fsType = "vfat"; };
  system.stateVersion = "26.05";
}
