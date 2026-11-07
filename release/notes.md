# Cybex OS 1.0.25

When a NixOS package update stops working with Cybex OS, as when NixOS removed Brave, Software Update now shows **Waiting for a Cybex OS update** with NixOS's reason instead of a failed update. Your current system keeps running, and the update is prepared again as soon as a Cybex OS release supports it. If one of your own modules in `/etc/nixos` is the cause, the message names that file.

ChatGPT now comes from NixOS's maintained package, so it moves to 26.1021 and stays current with your NixOS updates instead of waiting for a Cybex OS release.

Brave Origin updates now reach the beta channel automatically, usually within a day of each Brave stable release.

This is a source update with no new ISO. Installation, boot, physical hardware and staged-updater qualification are separate from source tests and package builds.
