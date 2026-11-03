# Cybex OS 1.0.14

- Clicking a workspace in the menubar switches to it again on Hyprland 0.57. Hyprland 0.57 changed how a display is told which workspace to show, so a click on a workspace that already had windows highlighted it without switching. Super+number and empty workspaces were not affected.

Validation covers source regressions (`tests/run`, QML lint), the workspace-modes fixture run against both Hyprland 0.56 and 0.57 behaviour, real menubar clicks in NixOS VMs running Hyprland 0.56.2 and 0.57.0 (two scaled displays, shared and per-display workspaces), Nix evaluation and the actual local staged-updater lifecycle in an isolated NixOS VM.

This is a source release with no new ISO attached. The existing 1.0.10 testing ISO retains its original source and does not contain these changes. Fresh ISO installation, applying the release through a published channel, a live session and physical hardware qualification have not been run for this release revision.
