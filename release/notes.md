# Cybex OS 1.0.22

Updates now arrive together. When a newer Cybex OS release comes out while an update is waiting to be installed, Software Update prepares it again in the background so both install with one restart. Newer NixOS packages alone refresh a waiting update once it is three days old. The update you already have stays installable until the new one is ready, and if preparing it again fails, the review says why.

Skipping releases no longer skips their notes. An update that jumps several versions shows what is new in each of them, newest first, in the review and in What's New.

This is a source update with no new ISO. Installation, boot, physical hardware and staged-updater qualification are separate from source tests and package builds.
