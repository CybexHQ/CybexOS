# Cybex OS 1.0.1

The first published Cybex OS release.

## Updates

- **Keyless releases.** A Cybex OS release is a published GitHub release of
  `CybexHQ/CybexOS`. Installed machines find the newest release on their
  channel through the GitHub API, pin its exact commit and the content hash of
  what they download, check the release's own `VERSION` and compatibility
  declaration, and refuse downgrades. There are no publisher keys or channel
  files. See `docs/releasing.md`.
- **Update health judges what an update changes.** A required service that was
  already failing before an update no longer rejects the update or the rollback
  after it, which could leave an update stuck in recovery.
- **Optional devices are reported, not required.** The XPS camera, touchpad
  haptics, Intel LPMd and speaker tuning are listed as `healthWarnings` in
  `cybex update status` when they do not run, and never hold back or roll back
  an update. Booting, networking, the login screen, the screen lock, the VPN
  daemon, XPS thermal protection and your own critical services remain
  required.

## Settings and installer

- **Settings → Security → Sudo** turns sudo without password on or off.
- The installer reports and guards restart and power-off requests, and the
  installer screen accepts touchpad taps.

## Upgrading from 1.0.0

Installations made before 1.0.1 accept only signed releases and cannot install
this one on their own. Reinstall from a 1.0.1 or newer medium, or move the
machine over once by hand.
