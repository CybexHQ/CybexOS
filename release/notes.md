# Cybex OS 1.0.11

- Installing or removing apps no longer restarts the desktop shell or Wiz. Both services used to name the system's package set in their PATH, so every app change restarted them: the screen blanked for a moment and an answer in progress was lost. They now follow the running system's profile, so a newly installed app is available to them immediately and app-only updates leave them running.
- Wiz is never restarted by an update. When Wiz itself is updated, it restarts into the new version after two idle minutes and keeps its last answer; with session-only history it waits for the next login. An update Wiz applies itself no longer ends its reply, and Wiz reports the result.
- `cybex update status` now says before applying when an update restarts the desktop shell (apps opened from the launcher or dock close with it) or Wiz, and Wiz passes that on before it applies an update.
- The Control Center button returns to the far right of the bar. Layouts that still start with it move it to the right; other placements are kept.

Validation covers source regressions, Nix evaluation and shared installation-contract parity, prebuilt-package checks, a new VM test that switches between system variants with the updater's own activation step (an app-only change keeps both services' processes and an answer in progress; a desktop change restarts only the shell; a Wiz change renews Wiz once idle; updater health checks pass after each), and the actual local staged-updater lifecycle in an isolated NixOS VM.

This is a source release with no new ISO attached. The existing 1.0.10 testing ISO retains its original source and does not contain these changes. Fresh ISO installation, applying the release through a published channel, and physical hardware qualification have not been repeated for this release revision.
