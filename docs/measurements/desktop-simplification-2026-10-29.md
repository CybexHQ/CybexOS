# Desktop simplification — 2026-10-29

This working-tree change removes the Mac-like desktop style, OPPO Sans and the
bundled wallpaper collection. Settings and first-run setup open on Wallhaven.
A fresh desktop has a plain background until an image is selected. Existing
personal images remain ordinary library files.

The Control Center footer now sizes itself from the scaled action buttons,
with room below their focus borders.

## Validation

- `nix develop -c tests/run` passed: 741 NixOS Python tests, 25 system-settings
  tests, 5 settings-ownership tests and 23 model-usage tests. Of 1507 Node
  tests, 1491 passed and 16 were skipped; none failed. The remaining plugin
  and live model-usage checks also passed.
- `nix flake check --no-build` passed. `tests/qml-lint` checked 443 QML files
  and 4 harnesses with no errors and the 8 existing warnings.
- The desktop and titlebar packages built successfully:
  `/nix/store/n48djq7l5fjnpk6msygzb782mj0bwjr0-cybexos-desktop-1.0.0-beta.19`
  and `/nix/store/mwg1s5giyz5bczpi7lfxq8ls1n2bm5lm-cybexos-titlebars-0.2.2`.
- `tests/wallpaper-picker.py` ran the real shell under private headless Sway.
  It checked the Wallhaven default, the empty initial wallpaper identity,
  personal image preview and keyboard apply, real Wallhaven listings/details,
  metering, and that previewing does not download an original image. All eight
  Control Center footer buttons fit at 100%, 125%, 150% and 200% shell scale.
  The shell log contained no QML errors.
- `tests/welcome-guide.py` passed under private headless Sway: a plain initial
  background, installer zoom at four output sizes, all six steps, wallpaper
  apply and palette generation, English and Dutch, keyboard navigation,
  stepping aside, and dismissal/resume across shell restart. Its online image
  download uses local fixtures; the picker test above contacts Wallhaven.
- The NixOS lifecycle VM test (`checks.x86_64-linux.vm.driver`, invoked with
  `--no-interactive` and `QEMU_OPTS=-no-user-config`) passed in 182.59 seconds.
  It exercised the real `cybex update stage local` worker, reached a ready
  candidate, preserved personal edits, discarded a regional candidate and
  detected an interrupted build. This is updater staging coverage, not
  installation or physical hardware qualification.
- The Dutch catalog has no missing or unused keys. Focused wallpaper-name
  and welcome-keybinding tests and `git diff --check` passed.

No ISO was built, no ISO/source parity check was run, and no physical hardware
or running workstation was changed. This Debian host has no Cybex desktop dev
service; isolated shells were started and restarted by the native harnesses.

All 12 task leases closed with no resources or errors remaining. Temporary
VM state, native-test directories, screenshots and task logs were removed;
no shell or QEMU process remained. Successful builds remain in the ordinary
Nix-managed cache.
