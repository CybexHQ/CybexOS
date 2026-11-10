{ lib, stdenv, fetchurl, autoPatchelfHook, installShellFiles,
  versionCheckHook, writableTmpDirAsHomeHook }:
# Codex from OpenAI's own release build: the codex-package archive its
# installer (https://chatgpt.com/codex/install.sh) installs, never compiled
# here, so an update does not wait for NixOS's build farm. release.json
# follows Codex's stable GitHub releases (rust-vX.Y.Z, not the alphas),
# updated by scripts/vendor-pins (the vendor-updates workflow) when GitHub's
# digest and OpenAI's codex-package_SHA256SUMS agree.
#
# The archive is upstream's package layout, kept whole in lib/codex: codex
# finds its code-mode host, exec server, sandbox (bwrap) and ripgrep beside
# itself through codex-package.json. Those are static binaries; only the
# voice helper and its private GStreamer runtime link glibc. From the Nix
# store Codex counts as neither a standalone nor a package-manager
# installation, so it offers no self-update command, as with Nixpkgs' codex.
let
  release = lib.importJSON ./release.json;
in
stdenv.mkDerivation {
  pname = "codex";
  inherit (release) version;

  src = fetchurl { inherit (release) url hash; };
  # The archive's top level is the package itself (bin/, codex-resources/...).
  sourceRoot = ".";

  dontConfigure = true;
  dontBuild = true;
  # Keep upstream's binaries as published; only the voice helper is patched.
  dontStrip = true;
  dontAutoPatchelf = true;
  strictDeps = true;

  nativeBuildInputs = [ autoPatchelfHook installShellFiles ];

  installPhase = ''
    runHook preInstall
    grep -q '"version": "${release.version}"' codex-package.json
    mkdir -p $out/lib/codex $out/bin
    cp -r bin codex-path codex-resources codex-package.json $out/lib/codex/
    chmod -R u+w $out/lib/codex
    # current_exe resolves this link, so codex still finds its package.
    ln -s ../lib/codex/bin/codex $out/bin/codex
    export HOME=$(mktemp -d)
    installShellCompletion --cmd codex \
      --bash <($out/bin/codex completion bash) \
      --fish <($out/bin/codex completion fish) \
      --zsh <($out/bin/codex completion zsh)
    runHook postInstall
  '';

  # Realtime voice runs a glibc helper with its own GStreamer libraries.
  postFixup = ''
    autoPatchelf $out/lib/codex/codex-resources/voice
  '';

  doInstallCheck = true;
  nativeInstallCheckInputs = [ writableTmpDirAsHomeHook versionCheckHook ];
  versionCheckKeepEnvironment = [ "HOME" ];

  meta = {
    description = "OpenAI's lightweight coding agent for the terminal (official release build)";
    homepage = "https://github.com/openai/codex";
    downloadPage = "https://github.com/openai/codex/releases";
    changelog = "https://github.com/openai/codex/releases/tag/rust-v${release.version}";
    license = lib.licenses.asl20;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = [ "x86_64-linux" ];
    mainProgram = "codex";
  };
}
