# Cybex OS 1.0.30

Updates with the newest NixOS packages no longer fail while building dictation. Those packages build Rust programs against the system's own libraries instead of bundled copies, and Cybex OS's dictation build (Voxtype with Parakeet) was missing two of them, Oniguruma and SQLite. It now includes both, so these updates go through again and dictation works as before.

This is a source update with no new ISO. Installation, boot, physical hardware and staged-updater qualification are separate from source tests and package builds.
