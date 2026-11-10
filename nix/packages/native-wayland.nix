# Keep the machine's prebuilt package intact. Both desktop entries and shell
# commands resolve this wrapper, including URL and private-window actions.
{ lib, symlinkJoin, makeWrapper }:
let
  wrap = { package, executable }: symlinkJoin {
    name = "${lib.getName package}-wayland-${lib.getVersion package}";
    inherit (package) pname version meta;
    paths = [ package ];
    nativeBuildInputs = [ makeWrapper ];
    postBuild = ''
      wrapProgram "$out/bin/${executable}" --add-flags --ozone-platform=wayland
    '';
    passthru = (package.passthru or {}) // {
      # NixOS's 1Password module supplies its polkit owners through override.
      override = args: wrap { package = package.override args; inherit executable; };
      # The download it wraps builds here too (nix/modules/prebuilt.nix).
      cybexosLocalBuilds = [ package ];
    };
  };
in wrap
