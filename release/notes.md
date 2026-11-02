# Cybex OS 1.0.9

- Installation recovery keeps the target filesystem and reports its location if it cannot be unmounted, preventing cleanup from deleting installed files.
- Restart, power off and firmware setup stay blocked while an installation continues after the installer screen's service restarts.
- Interrupted configuration copies no longer leave incomplete personal-module backups that recovery could accept as complete.
- Software keeps Flathub operations in progress when the service manager is unreachable, prevents overlapping requests during slow startup, and preserves the worker's result if its startup command times out.
- Installation media can start from a Ventoy USB stick in normal and grub2 modes, fixing the missing `init=` boot parameter.

This is a source release with no new ISO attached. The existing 1.0.8 testing ISO uses its original source and does not contain the later reliability fixes above. Installed-system, boot and physical hardware qualification has not been repeated for this release revision.
