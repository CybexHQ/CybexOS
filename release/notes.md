# Cybex OS 1.0.16

- Updates are held back again when NixOS has not built a package yet. Nix 2.34, in current nixos-unstable, describes some packages in a new format, and the prebuilt-package check misread them as configuration files. Such a package could therefore reach a build on your computer. opencode 2.2.5 did: its upstream dependency checksum is wrong, so the whole update failed with "hash mismatch in fixed-output derivation". The update now stops before building and reports "Waiting for NixOS to finish building this change" with the package names. Your installed system was never changed by the failed update.
- If an update failed this way: stage Cybex OS only (`cybex update stage cybexos`) to keep your current Nixpkgs, or prepare the full update again once NixOS has built the fixed opencode.

Validation covers source regressions (`python3 -m unittest discover tests/nixos`, including new cases for Nix 2.34's derivation format), the prebuilt-package check, the updater's prebuilt guard run with Nix 2.34.9 against an update to nixos-unstable 1d060086 (it now reports `opencode-2.2.5`; before the fix it reported nothing), and the actual local staged-updater lifecycle in an isolated NixOS VM.

This is a source release with no new ISO attached. Existing testing ISOs keep their original source and do not contain this change. Fresh ISO installation, applying the release through a published channel and physical hardware qualification have not been run for this release revision.
