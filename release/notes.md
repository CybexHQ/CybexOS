# Cybex OS 1.0.21

Local configuration changes now stop before rebuilding a Linux kernel image, closing an additional path covered by the stock-kernel policy. Personal declarations and machine-owned locks remain unchanged when a change is refused.

Software now identifies which queued app requires a kernel build. Other apps in the same queue are no longer incorrectly marked as requiring that build.

A refused personal change now shows the failure and asks you to correct it. It no longer appears as “Waiting for NixOS packages”; that message remains available for source updates waiting for cached packages.

This is a source update with no new ISO. Installation, boot, physical hardware and staged-updater qualification are separate from source tests and package builds.
