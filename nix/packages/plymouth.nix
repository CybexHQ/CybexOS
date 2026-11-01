{ lib, stdenvNoCC, librsvg, source }:
stdenvNoCC.mkDerivation {
  pname = "cybexos-plymouth";
  # Not the release version: the splash is in every boot's early image, so a
  # release that leaves it alone must leave that image identical, and the
  # updater then installs the release without a test boot.
  version = "1";
  src = import ../package-source.nix {
    inherit lib source;
    paths = [ "desktop/plymouth" "assets/wiz" ];
  };
  nativeBuildInputs = [ librsvg ];
  dontBuild = true;
  installPhase = ''
    runHook preInstall
    theme=$out/share/plymouth/themes/cybexos
    mkdir -p "$theme"
    cp desktop/plymouth/*.png desktop/plymouth/cybexos.script desktop/plymouth/cybexos.plymouth "$theme/"
    substituteInPlace "$theme/cybexos.plymouth" \
      --replace-fail /usr/share/plymouth/themes/cybexos "$theme"
    # Wiz on the disk unlock prompt (cybexos.script): his poses at rest, all
    # in one box (WizRig.STILL_BOX, 136×132), 84 pixels high, so he stands
    # about 65 pixels tall. The script plugin draws every image at one pixel
    # per logical pixel, the logo included.
    for pose in asleep listening sorry happy; do
      rsvg-convert --height 84 --output "$theme/wiz-$pose.png" "assets/wiz/$pose.svg"
    done
    # The installation medium's variant: the same pictures and script, which
    # shows the medium's boot progress once the first line flags it.
    installer=$out/share/plymouth/themes/cybexos-installer
    mkdir -p "$installer"
    { echo 'global.installation_medium = 1;'; cat desktop/plymouth/cybexos.script; } > "$installer/cybexos-installer.script"
    cp desktop/plymouth/cybexos-installer.plymouth "$installer/"
    substituteInPlace "$installer/cybexos-installer.plymouth" \
      --replace-fail /usr/share/plymouth/themes/cybexos-installer "$installer" \
      --replace-fail /usr/share/plymouth/themes/cybexos "$theme"
    runHook postInstall
  '';
  meta = { description = "Cybex OS boot splash and encrypted-disk unlock theme"; license = lib.licenses.mit; platforms = lib.platforms.linux; };
}
