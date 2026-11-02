# Cybex OS branding

The NerdOS rename is reverted. Interface text says **Cybex OS**. Repository,
NixOS module/input, Python package, service, path and protocol identifiers use
`cybexos`; the environment prefix is `CYBEXOS_` and the user command is `cybex`.
The upstream repository and release identity are `CybexHQ/CybexOS` (`REPO` in
`lifecycle/cybexos/trust.py`); its GitHub releases are the update channels.
Development moved there from `DigitalPals/CybexOS` on
2026-10-29; the earlier history stays in that repository.

The owner-supplied `cybex_white.svg` is preserved byte-for-byte under
`assets/brand/source/`. Deployment variants use its outlined wordmark with
the original red `#DC1E37`; small icons use the two X paths from that same
drawing. The installer, desktop, assistant, fastfetch, browser demo,
application icons and favicons share these assets. `scripts/export-brand.py`
regenerates them and their SHA-256 manifest using Pillow and librsvg from the
locked Nixpkgs.

Plymouth is packaged and selected by the shared NixOS installation module for
the ISO and installed system. Its wordmark is 189×44 (378×88 at double
density), approximately 66% of the 286-pixel password field width and retaining
the source aspect ratio. Password masking, callback, display recentering and boot
progress behavior are preserved. Progress and selected items are blue.
Installed systems show the progress bar only after a disk unlock. The
installation medium's variant, `cybexos-installer`, is the same script and
pictures with one line prepended (`nix/packages/plymouth.nix`). It shows the bar
from its first frame, where the passphrase field would be
([installation](installation.md)).

The boot menus share that wordmark and keep its centre 38% from the top, where
Plymouth draws it too, so the logo does not move from menu to splash. Both
use a black background, as firmware logo screens do: GRUB's plain terminal,
shown while a hidden menu loads the system, cannot use any other colour.
`desktop/boot/theme.py` builds the GRUB theme at Nix build time for both the ISO
and installed systems: a card of Space Grotesk entries (GRUB's 1-bit PF2 fonts,
one fixed size) with Tabler 3.48.0 icons (`desktop/boot/icons.json`, refreshed
by `scripts/update-installer-icons`) and a tinted blue selection. Headings, key
hints and notices are static, so they are pre-rendered with anti-aliasing in
Space Grotesk and JetBrains Mono. GRUB sizes a list from its theme, so each
list comes in row variants that the menus choose. The ISOLINUX screen for a
legacy BIOS start is the same build's 800×600 notice.

### Wiz in the terminal, not on the password screens

Wiz, the assistant's character (docs/assistant.md), appears in the terminal
as a still picture of a pose: `scripts/export-wiz` writes each pose at rest to
`assets/wiz/<pose>.svg`, and the desktop package renders the one it needs with
librsvg at build time. He never speaks, and the boot logo stays the Cybex mark.

- **Terminal.** Typing a plain `fastfetch` at fish's prompt in kitty shows Wiz
  (`idle`, 9 rows high) through kitty's graphics protocol. The default
  fastfetch config's logo is `$CYBEXOS_FASTFETCH_LOGO`, else the braille
  logo; fish's `fastfetch` function sets it only when the config names it,
  the shell runs in kitty itself, fastfetch writes to the terminal, there are
  no arguments and `NO_COLOR` is unset. Where fastfetch cannot draw a picture
  it would print the file as text, so other terminals, tmux, ssh, pipes and
  `command fastfetch` keep the braille logo.
- **Disk unlock and lock screen.** Neither shows Wiz (removed in November
  2026). Plymouth's passphrase field sits 40 pixels under the logo, and
  hyprlock shows the clock, the date and the centred password field.

`checks.x86_64-linux.plymouth-unlock` unlocks a LUKS volume in a real
systemd initrd through the packaged theme with a wrong and then the right
passphrase, and shows it at double scale, checking that nothing is drawn
between the logo and the field; `checks.x86_64-linux.lock-terminal` locks a
signed-in desktop with both lock screens, checks that no picture is beside
the field, and runs fastfetch in kitty. Both take screenshots for review;
they are VM qualification, not of physical displays.

### The Control Center button and the prompt icon

The Control Center button starts the bar's left column, in its top-left
corner before the launcher, and its drawer opens on that side. Settings ->
Bar & Control Center -> Control Center -> Button icon chooses its icon: the
Cybex OS mark (the default), the operating system's logo (NixOS), or any Nerd
Font icon, searched by name in `desktop/quickshell/assets/nerd-icons`
(regenerate with `scripts/update-nerd-icons` when Nixpkgs moves to a new
Nerd Fonts release). The fish prompt shows the same icon: the shell writes it
to `~/.local/state/cybexos/prompt-icon`, which fish reads with builtins before
each prompt. The Cybex OS mark reaches terminals through Cybex OS Symbols, a
one-glyph font built from the brand's monochrome symbol at U+1000CB
(`scripts/build-symbols-font.py`, `nix/packages/symbols-font.nix`). Choosing
the operating system, or turning off "Use in terminal prompt", leaves the
prompt its own per-distribution icon, so a Distrobox shows its distribution.

The graphical and terminal installers, timezone map, password dialog and
brand controls use blue with charcoal text. New desktop preferences, the
Cybex OS theme, terminal fallback, window borders and lock screen default to
blue. Existing personal preferences and selectable wallpaper palettes remain
user owned; this source update never rewrites them.

This targets fresh installations under the repository lifecycle contract.
There are no old-name aliases or in-place conversion scripts. The previous
rename report, screenshots and measurements remain explicitly historical;
upstream Nerd Font family/package names retain their original spelling.

## Verification

The initial rename was validated on thebeast on 2026-10-24 using the locked
Nix development environment. The later logo refinement is recorded separately.

- `nix flake check --no-build` passed, including evaluation of the retained
  NVIDIA and XPS hardware configurations. The installation-contract parity,
  lifecycle checks, Plymouth package, installer and VM driver built successfully.
- The Nix lifecycle check passed 551 Python tests (including six artwork
  integrity/geometry/contrast tests), the Hermes/agent/camera fixtures and
  21 system-settings tests. `tests/nixos-native` passed its real Nix/Git,
  authenticated HTTPS, exact-input preservation, private-store source-transfer
  and retention checks.
- The native installer passed 20 unit, six UI interaction and four presentation
  tests. Its actual Slint software renderer produced welcome, account, timezone
  and installation-progress fixtures for visual review. The longer hostname
  suffix is bounded to the existing 31-character limit in both UI and daemon.
- The booted NixOS lifecycle VM passed in 100 seconds under `agent-resource`.
  It exercised the renamed services/CLI, networking defaults, personal setup,
  desktop checker, real supervised software and maintenance staging, and
  unchanged personal files/locks. The packaged Plymouth script rendered the
  supplied wordmark and masked password entry, accepted its real password
  callback, and reported no theme load/parse errors. The host invocation used
  `QEMU_OPTS=-no-user-config`; all guest disks and processes were disposable.
- QML lint passed 376 files and four harnesses, with no errors and eight
  existing warnings. The Quickshell Node suite passed 1,360 tests with 17
  skipped; the affected theme checks were rerun after updating the blue
  fallback palettes (43 passed, six skipped). Theme-pack canonicalization,
  plugin transactions and Model Usage integration checks passed too.
- The browser demo passed lint, TypeScript, all 116 component tests, production
  build and two production Worker tests. Its existing `cybexos-web` development
  service was rebuilt/restarted and is healthy on port 5174.

Both managed VM leases closed with no remaining resources. Temporary renders,
VM disks, test logs and local web build/dependency outputs were removed after
review; the existing development service remains running.

The subsequent logo refinement restored the source SVG's red `#DC1E37` in
coloured logos, terminal art and hover variants while retaining blue interface
controls/progress. That pass matched the logo to its 286-pixel input width.
All six artwork checks and three brand-registry checks passed, as did the
30 native installer tests and the package/parity builds. The full lifecycle
VM was rerun successfully in 110 seconds, including the real Plymouth password
callback and staged software/maintenance updates. New native installer and
Plymouth VM screenshots were reviewed and embedded in the conversation.
The browser development service was rebuilt and its served logo colours
verified. The managed VM lease closed with no remaining resources; temporary
captures and logs were removed after review.

The final sizing pass reduced the Plymouth wordmark to 189×44 pixels,
approximately 66% of the previous 286×67 size (378×88 at double density).
Only the two Plymouth logo rasters changed among the deployed artwork.
All six artwork checks and the package/parity builds passed; the full lifecycle
VM passed again in 119 seconds, including password submission and staged
updates. Its new screenshot was embedded in the conversation. The managed
lease closed without remaining resources, and temporary captures/logs were
removed after review.

These checks do not establish fresh ISO installation, encrypted-disk boot or
physical hardware qualification for this revision. No new ISO, published
release or host OS activation was performed. `flake.lock` and the dependency
versions in the Cargo/npm locks were retained. Release qualification continues
to require the same committed revision/NAR for artifacts and tests.

Committed development media carries its Git revision in the live release
metadata. The development installer locks the exact bundled directory as a
path input; Nix retains its NAR hash but gives that flake no Git revision, so
the installed release reports `uncommitted`. Installation qualification checks
the ISO, installed release and installed input lock against the same NAR and
records both release identities. Git-backed inputs still require the exact
revision as well as the NAR. This does not authenticate an unpublished build.
