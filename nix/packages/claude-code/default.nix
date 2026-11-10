{ lib, stdenvNoCC, fetchurl, autoPatchelfHook, makeBinaryWrapper, zstd,
  alsa-lib, procps, ripgrep, bubblewrap, socat,
  versionCheckHook, writableTmpDirAsHomeHook }:
# Claude Code from Anthropic's own native build: the binary its installer
# (https://claude.ai/install.sh) downloads from downloads.claude.ai, never
# compiled here, so an update does not wait for NixOS's build farm.
# release.json follows Anthropic's `latest` channel, updated by
# scripts/vendor-pins (the vendor-updates workflow) after it has checked the
# release's signed manifests. The download is checked against
# manifest.zst.json by its fixed hash; the unpacked binary against
# manifest.json below. The wrapper matches Nixpkgs' claude-code: Cybex OS
# updates Claude Code, Claude Code does not update or relocate itself.
let
  release = lib.importJSON ./release.json;
in
stdenvNoCC.mkDerivation {
  pname = "claude-code";
  inherit (release) version;

  src = fetchurl { inherit (release) url hash; };

  dontUnpack = true;
  dontBuild = true;
  # A Bun single-file executable carries the application after the runtime:
  # stripping it leaves the bare Bun runtime.
  dontStrip = true;
  strictDeps = true;

  nativeBuildInputs = [ autoPatchelfHook makeBinaryWrapper zstd ];

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin
    zstd -d -q $src -o $out/bin/claude
    echo "${release.binarySha256}  $out/bin/claude" | sha256sum --check --quiet
    chmod 755 $out/bin/claude
    # Cybex OS updates Claude Code: `claude update` would install a second,
    # untracked copy into the home folder, so it is off with the auto-updater.
    wrapProgram $out/bin/claude \
      --set DISABLE_AUTOUPDATER 1 \
      --set DISABLE_UPDATES 1 \
      --set-default FORCE_AUTOUPDATE_PLUGINS 1 \
      --set DISABLE_INSTALLATION_CHECKS 1 \
      --set USE_BUILTIN_RIPGREP 0 \
      --set-default CLAUDE_CODE_CERT_STORE system \
      --prefix LD_LIBRARY_PATH : ${lib.makeLibraryPath [ alsa-lib ]} \
      --prefix PATH : ${lib.makeBinPath [
        # Process-tree cleanup (ps), search, and the sandbox's helpers.
        procps ripgrep bubblewrap socat
      ]}
    runHook postInstall
  '';

  doInstallCheck = true;
  nativeInstallCheckInputs = [ writableTmpDirAsHomeHook versionCheckHook ];
  versionCheckKeepEnvironment = [ "HOME" ];
  versionCheckProgramArg = "--version";

  meta = {
    description = "Anthropic's agentic coding tool for the terminal (official native build)";
    homepage = "https://github.com/anthropics/claude-code";
    downloadPage = "https://code.claude.com/docs/en/setup";
    changelog = "https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md";
    license = lib.licenses.unfree;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = [ "x86_64-linux" ];
    mainProgram = "claude";
  };
}
