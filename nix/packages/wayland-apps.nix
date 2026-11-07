{ pkgs }:
let
  nativeWayland = pkgs.callPackage ./native-wayland.nix {};
in {
  spotify = nativeWayland { package = pkgs.spotify; executable = "spotify"; };
  chatgpt = nativeWayland { package = pkgs.chatgpt; executable = "chatgpt"; };
  _1password-gui = nativeWayland { package = pkgs._1password-gui; executable = "1password"; };
}
