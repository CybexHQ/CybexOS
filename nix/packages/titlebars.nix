{ lib, hyprland, hyprlandPlugins, fetchurl, cmake, binutils }:
let
  # The renderer/window API changed in 0.57. Follow the machine's prebuilt
  # compositor and select the upstream implementation for that API.
  modern = lib.versionAtLeast hyprland.version "0.57";
  revision = if modern then "b351b14bbed4b04ed55e6380e03784edcee68399"
             else "379ff910fcce9f0cc9b41f9a87c527997076a417";
in
hyprlandPlugins.mkHyprlandPlugin {
  pluginName = "cybexos-titlebars";
  version = if modern then "0.3.0" else "0.2.2";
  inherit hyprland;
  src = fetchurl {
    name = "omarchy-titlebars-${builtins.substring 0 7 revision}.tar.gz";
    url = "https://codeload.github.com/omacom/omarchy-hyprland-titlebars/tar.gz/${revision}";
    sha256 = if modern then "b0f9d943da34cdeec56dac70661d86e94f63eaf2ef3c7f327b13b6fb1f9cc4fd"
             else "a453ae6b0a39f75e9a559a0258746e7df24a9432d5571ce505501cd0a333aa72";
  };
  patches = [ (if modern then ../../desktop/hypr/titlebars-native-057.patch
               else ../../desktop/hypr/titlebars-native.patch) ];
  nativeBuildInputs = [ cmake binutils ];
  preConfigure = ''
    # Nixpkgs' public binary is a Qt wrapper. The guard identifies the actual
    # compositor ELF, built with the same derivation and headers as this plugin.
    compositor=${hyprland}/bin/.Hyprland-wrapped
    test -e "$compositor" || compositor=${hyprland}/bin/Hyprland
    build_id=$(readelf -n "$compositor" | sed -n 's/.*Build ID: //p')
    test -n "$build_id"
    cmakeFlagsArray+=("-DCYBEXOS_HYPRLAND_BUILD_ID=$build_id")
  '';
  meta = { license = [ lib.licenses.mit lib.licenses.bsd3 ]; };
}
