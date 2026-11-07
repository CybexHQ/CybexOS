{ lib, callPackage,
  # Keep the former shortcut flags in the package, so desktop-entry launches,
  # private actions and the selected-browser helper retain camera/IME support.
  commandLineArgs ? "--enable-features=TouchpadOverscrollHistoryNavigation,PipeWireCamera,AcceleratedVideoDecodeLinuxGL,AcceleratedVideoEncoder --enable-wayland-ime --restore-last-session --hide-crash-restore-bubble"
}:
# Nixpkgs no longer packages Brave (NixOS/nixpkgs#582838), so Cybex OS keeps
# its recipe (make-brave.nix) and builds the official Origin Debian asset with
# the machine Nixpkgs' libraries. It keeps Brave's desktop and executable
# names, which the browser defaults and the 1Password host check expect.
# Cybex OS is the browser's only maintainer: release.json follows every Brave
# stable release, updated by scripts/vendor-pins (the vendor-updates workflow).
let
  release = lib.importJSON ./release.json;
  inherit (release) version;
  brave = callPackage (import ./make-brave.nix {
    pname = "brave";
    inherit version;
    archives.x86_64-linux = { inherit (release) url hash; };
    flavor = "browser";
    optStem = "brave";
    fileStem = "brave-browser";
    appIdStem = "com.brave.Browser";
    darwinStem = "Brave Browser";
    changelogFile = "CHANGELOG_DESKTOP_ORIGIN.md";
    homepage = "https://brave.com/origin/";
    innerBinary = "brave";
  }) { inherit commandLineArgs; };
in
brave.overrideAttrs (old: {
  pname = "brave-origin";
  # Normalize upstream's edition-specific paths for the recipe's names.
  postPatch = (old.postPatch or "") + ''
    mv opt/brave.com/brave-origin opt/brave.com/brave
    mv opt/brave.com/brave/brave-origin opt/brave.com/brave/brave-browser
    mv usr/share/applications/brave-origin.desktop usr/share/applications/brave-browser.desktop
    mv usr/share/applications/com.brave.Origin.desktop usr/share/applications/com.brave.Browser.desktop
    mv usr/share/gnome-control-center/default-apps/brave-origin.xml usr/share/gnome-control-center/default-apps/brave-browser.xml
    substituteInPlace usr/share/applications/{brave-browser,com.brave.Browser}.desktop \
      --replace-fail /usr/bin/brave-origin-stable /usr/bin/brave-browser-stable
    substituteInPlace opt/brave.com/brave/default-app-block \
      usr/share/gnome-control-center/default-apps/brave-browser.xml \
      --replace-fail /opt/brave.com/brave-origin /opt/brave.com/brave
  '';
  postInstall = (old.postInstall or "") + ''
    ln -s brave $out/bin/brave-origin-stable
    ln -s brave-browser.desktop $out/share/applications/brave-origin.desktop
    ln -s com.brave.Browser.desktop $out/share/applications/com.brave.Origin.desktop
    for icon in $out/share/icons/hicolor/*/apps/brave-browser.png; do
      ln -s brave-browser.png "$(dirname "$icon")/brave-origin.png"
    done
  '';
  meta = old.meta // {
    description = "Brave Origin privacy-oriented browser";
    platforms = [ "x86_64-linux" ];
  };
})
