# Cybex OS 1.0.10

- Closed-lid laptops stay awake when a connected external display blanks through DPMS or drops its DisplayPort connection briefly. A three-second disconnect grace matches the existing display helper. Sustained disconnection still suspends through the existing lock path, and closing an undocked laptop still suspends immediately.
- The display-aware lid guard retains protection across service restarts and participates in updater health checks. Manual suspend and battery-only idle suspend keep their existing behavior.
- Dictation shows live words in a recording pill, offers an optional enhanced model, and adds language and live-text choices. The Voxtype fixes preserve recording audio and keep typing focused on the original application. Updates allow the product's patched dictation engine to build locally while keeping Nixpkgs dependencies subject to the prebuilt check.
- Wiz gains a wide conversation view, change tracking with Undo, clearer approvals and progress, notifications, desktop tools and scheduled routines.
- Settings offers a choice of Control Center icon. Disk-unlock and session-lock screens no longer draw Wiz; kitty's system summary retains the character.

Validation covers source regressions, Nix evaluation and shared installation-contract parity, prebuilt-package checks, a real-logind lid regression VM, and the actual local staged-updater lifecycle in an isolated NixOS VM. The lid VM uses fixture DRM status files and a replacement for the final sleep operation; it does not qualify physical display hotplug or firmware suspend/resume.

This is a source release with no new ISO attached. The existing 1.0.8 testing ISO retains its original source and does not contain these changes. Fresh ISO installation, applying the release through a published channel, and physical hardware qualification have not been repeated for this release revision.
