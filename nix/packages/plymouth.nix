{ lib, stdenvNoCC, librsvg, source }:
stdenvNoCC.mkDerivation {
  pname = "cybexos-plymouth";
  version = lib.trim (builtins.readFile (source + /VERSION));
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
    runHook postInstall
  '';
  meta = { description = "Cybex OS boot splash and encrypted-disk unlock theme"; license = lib.licenses.mit; platforms = lib.platforms.linux; };
}
