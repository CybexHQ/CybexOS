# Omasnap, Omarchy's screenshot and annotation overlay for Hyprland
# (https://github.com/omacom/omasnap, MIT). Nixpkgs does not package it, so
# Cybex OS builds this pinned release itself, as it builds Omawrite.
#
# Omasnap expects three Omarchy pieces; this package supplies Cybex OS ones:
# - Notifications go to `omarchy-notification-send`. The wrapper puts
#   omasnap-notify.sh first on Omasnap's own PATH under that name, and it
#   hands them to the session's notification server through notify-send.
# - Its chrome follows Omarchy's theme directory. It reads the colours the
#   shell renders into ~/.local/state/cybexos/theme/omasnap instead
#   (desktop/quickshell/scripts/theme_omasnap.py).
# - Wording comes from `omarchy-i18n` where present; without it, English.
#
# The smoke suite is long to compile, so machines build without it and
# `checks.<system>.omasnap` runs it (passthru.tests.smoke).
{ lib, stdenv, fetchFromGitHub, cmake, ninja, pkg-config, qt6, kdePackages,
  wayland, wayland-scanner, wayland-protocols, libdeflate,
  hyprland, wl-clipboard, tesseract, xdg-utils, libnotify, bash, coreutils,
  makeFontsConf, dejavu_fonts, fontconfig }:
stdenv.mkDerivation (finalAttrs: {
  pname = "omasnap";
  version = "1.25.0";
  src = fetchFromGitHub {
    owner = "omacom";
    repo = "omasnap";
    tag = "v${finalAttrs.version}";
    hash = "sha256-tFnTqAGKmNHQqjPsBq/XvgRh/5jXiD0Mxj6h1SLEpyI=";
  };
  postPatch = ''
    substituteInPlace CMakeLists.txt \
      --replace-fail /usr/share/wayland-protocols ${wayland-protocols}/share/wayland-protocols
    substituteInPlace src/chrome-theme.cpp \
      --replace-fail '".local/state/omarchy/current/theme"' '".local/state/cybexos/theme/omasnap"'
    # The smoke tests write helper scripts; the build sandbox has /bin/sh only.
    substituteInPlace tests/*.cpp \
      --replace-quiet "/usr/bin/env bash" "${bash}/bin/bash" \
      --replace-quiet /bin/cat "${coreutils}/bin/cat"
  '';
  strictDeps = true;
  nativeBuildInputs = [ cmake ninja pkg-config wayland-scanner qt6.wrapQtAppsHook ];
  buildInputs = [ qt6.qtbase qt6.qtwayland kdePackages.layer-shell-qt wayland libdeflate ];
  cmakeFlags = [ (lib.cmakeBool "BUILD_TESTING" finalAttrs.doCheck) ];
  doCheck = false;
  nativeCheckInputs = [ bash coreutils tesseract ];
  # Run the suite directly: ctest hides its output, and a failed check's
  # exit status is that check's number in tests/editor-smoke.cpp.
  checkPhase = ''
    runHook preCheck
    export QT_QPA_PLATFORM=offscreen QT_FORCE_STDERR_LOGGING=1 HOME=$TMPDIR
    export XDG_RUNTIME_DIR=$TMPDIR/run
    mkdir -p -m 0700 $XDG_RUNTIME_DIR
    # A monospace face that reports fixed pitch (Noto Sans Mono does not).
    export FONTCONFIG_FILE=${makeFontsConf {
      fontDirectories = [ dejavu_fonts ];
      includes = [ "${fontconfig.out}/etc/fonts/conf.d" ];
    }}
    ./omasnap-smoke --output-dir $TMPDIR/smoke-output
    runHook postCheck
  '';
  postInstall = ''
    install -Dm755 ${./omasnap-notify.sh} $out/libexec/omasnap/omarchy-notification-send
    substituteInPlace $out/libexec/omasnap/omarchy-notification-send \
      --replace-fail @bash@ ${bash}/bin/bash \
      --replace-fail @notify-send@ ${libnotify}/bin/notify-send
  '';
  # The session's own hyprctl and wl-clipboard come first: hyprctl must
  # match the running compositor.
  qtWrapperArgs = [
    "--prefix" "PATH" ":" "${placeholder "out"}/libexec/omasnap"
    "--suffix" "PATH" ":" (lib.makeBinPath [ hyprland wl-clipboard tesseract xdg-utils ])
  ];
  passthru.tests.smoke = finalAttrs.finalPackage.overrideAttrs { doCheck = true; };
  meta = {
    description = "Wayland screenshot and annotation overlay for Hyprland";
    homepage = "https://github.com/omacom/omasnap";
    license = lib.licenses.mit;
    mainProgram = "omasnap";
    platforms = lib.platforms.linux;
  };
})
