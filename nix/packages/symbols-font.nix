# Cybex OS Symbols: the Cybex OS mark as a one-glyph font, so terminals can
# draw it in the fish prompt through fontconfig's fallback
# (scripts/build-symbols-font.py). Built from the brand's monochrome symbol.
{ lib, stdenvNoCC, python3, source }:
stdenvNoCC.mkDerivation {
  pname = "cybexos-symbols-font";
  version = "1";
  src = import ../package-source.nix {
    inherit lib source;
    paths = [ "scripts/build-symbols-font.py" "assets/brand/symbol/svg/cybexos-symbol-mono-white.svg" ];
  };
  nativeBuildInputs = [ (python3.withPackages (p: [ p.fonttools ])) ];
  dontConfigure = true;
  buildPhase = ''
    runHook preBuild
    python3 scripts/build-symbols-font.py assets/brand/symbol/svg/cybexos-symbol-mono-white.svg CybexOSSymbols.ttf
    runHook postBuild
  '';
  installPhase = ''
    runHook preInstall
    install -Dm444 CybexOSSymbols.ttf $out/share/fonts/truetype/CybexOSSymbols.ttf
    runHook postInstall
  '';
  meta = { description = "Cybex OS mark as a private-use glyph for terminal prompts"; license = lib.licenses.mit; platforms = lib.platforms.all; };
}
