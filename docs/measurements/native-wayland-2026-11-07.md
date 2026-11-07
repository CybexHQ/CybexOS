# Native Wayland launchers — 2026-11-07

The launcher changes are based on Cybex OS commit
`eae1a88ec5a1ab364fb87ca11af74ae1c72425dc` (1.0.25), with the unchanged
Nixpkgs lock at `31ecbaca1bdefa45dffc409f0250bd8039ea0010`.

Spotify, 1Password and Nixpkgs' ChatGPT use small executable wrappers around
the original packages. Brave Origin and T3 Code add the same explicit
`--ozone-platform=wayland` flag to their existing launchers. Software selects
the same wrappers. The ChatGPT AppArmor profile still names the original
executable, and 1Password's package override still supplies its polkit owners.

## Checks exercised

- Built Spotify 1.2.95.453.g0eeebbed, 1Password 8.12.42 (with test polkit owner
  `tester`), ChatGPT 26.1021.22027, Brave Origin 1.99.55 and the pinned T3 Code
  nightly with the new launchers. Inspected the actual executable wrappers
  and desktop entries, and verified the generated 1Password polkit owners.
- Launched Spotify through its packaged `spotify.desktop` using `gio launch`
  with the wrapper first in `PATH`. The isolated Sway 1.12 session used a
  headless output, software rendering, a separate D-Bus session and temporary
  home/XDG directories. `NIXOS_OZONE_WL` was unset and XWayland was disabled.
  Sway reported a window with `app_id: spotify`, `shell: xdg_shell` and
  `name: Spotify`. No Spotify account or existing profile was used.
- Evaluated the product plus Software selections for Spotify, ChatGPT and
  1Password: the wrappers were selected, the configured polkit owner reached
  the 1Password package, and ChatGPT's AppArmor rule retained the original
  executable path.
- `scripts/check-prebuilt` passed with eight pointer downloads checked and
  no unexpected Nixpkgs compilation. ChatGPT's original unfree package is an
  expected local build because AppArmor references it separately from the
  installed wrapper.
- The shared ISO/installed-system `parity` check built successfully, and
  `nix flake check --no-build --no-write-lock-file --option eval-cache false`
  passed.
- The components of `tests/run` passed across two environments. The primary
  Python run exercised 1,109 tests with two skipped; its only failure was the
  known default-applications fixture reading the host's desktop entries.
  All 16 default-applications tests passed in a Bubblewrap namespace hiding
  those entries, with a private `/dev`. The remaining helper suites passed
  in the normal environment. JavaScript reported 1,687 passed, 15 skipped
  and zero failures. No single `tests/run` invocation passed without this
  environment split.
- Ran the actual updater's `Engine.stage("local")` with its normal Runner,
  real Nix commands and a disposable machine configuration and state
  directory. The configuration imported the shared module and test machine,
  enabled proprietary applications and selected Spotify/ChatGPT through
  Software. It used the source snapshot
  `sha256-ps7t/uLJrMbMlLRoV6C8xdxSS1kQMceHpdxoInOxQW4=` and the unchanged
  Nixpkgs lock above. Preparation reached `ready`, including the kernel
  prebuilt guard, complete system build, isolated Hyprland and offscreen QML
  checks, package review and review token generation. The initial unprivileged
  attempt could not overwrite a read-only copied smoke fixture; rerunning
  under the updater's normal root privileges succeeded. No personal machine
  configuration was copied into this test, and no candidate was applied.

The headless test establishes Spotify's native backend selection, not display
sharpness, pointer appearance, audio, authentication or physical GPU behavior.
The updated `wayland-scale` VM check was not run. The staged preview used an
isolated test configuration; it does not qualify an installed machine's
update, activation or hardware. No system activation, installation, ISO build,
release publication or reboot was performed. The temporary compositor,
clients, D-Bus session, profile and staging state were stopped or removed
after testing; the running desktop and personal configuration were not
changed. Documentation of the results was added after the staged source
snapshot; the tested product code was unchanged.
