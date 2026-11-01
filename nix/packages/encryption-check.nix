# The check that permits automatic login only on encrypted storage
# (pam.d/sddm-autologin). It is its own package, built from its own file and
# named without the release version, so the login screen changes only when
# this check does; a release that leaves it alone needs no test boot.
{ lib, stdenvNoCC, makeWrapper, python3, util-linux, btrfs-progs, source }:
stdenvNoCC.mkDerivation {
  pname = "cybexos-encryption-check";
  version = "1";
  src = import ../package-source.nix {
    inherit lib source;
    paths = [ "lifecycle/bin/cybexos-verify-encryption" ];
  };
  nativeBuildInputs = [ makeWrapper ];
  buildInputs = [ python3 ];
  dontBuild = true;
  installPhase = ''
    runHook preInstall
    install -Dm755 lifecycle/bin/cybexos-verify-encryption $out/bin/cybexos-verify-encryption
    runHook postInstall
  '';
  # PAM runs it with an empty environment: name its interpreter and tools.
  postFixup = ''
    wrapProgram $out/bin/cybexos-verify-encryption --set PATH ${lib.makeBinPath [ util-linux btrfs-progs ]}
  '';
  meta = { description = "Cybex OS encrypted-storage check for automatic login"; license = lib.licenses.mit; platforms = lib.platforms.linux; };
}
