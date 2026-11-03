# Cybex OS 1.0.13

- The Control Center button is back at the far right of the menubar. Updating moves it there once from wherever an earlier version left it, for example after the music player, and keeps whether it is shown. You can still move it yourself afterwards.
- A widget dragged to another section of the menubar now stays there. The settings file used to keep a copy in its old section, and that copy won the next time the settings loaded.
- Restoring the default widget layout works on the first click and stays restored. It used to keep every widget placed outside its default section, so the layout was rebuilt around those widgets right after the reset, and again after a restart or the next settings change. Leftovers saved by an earlier reset are ignored.

Validation covers source regressions (`tests/run`, QML lint), new unit and QML-engine tests of the layout save, reset and reload, Nix evaluation, the shared installation-contract parity check and the actual local staged-updater lifecycle in an isolated NixOS VM.

This is a source release with no new ISO attached. The existing 1.0.10 testing ISO retains its original source and does not contain these changes. Fresh ISO installation, applying the release through a published channel, a live session and physical hardware qualification have not been run for this release revision.
