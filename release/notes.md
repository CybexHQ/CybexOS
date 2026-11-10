# Cybex OS 1.0.27

A new Cybex OS release no longer waits for NixOS packages. When NixOS hasn't finished building some of its newer packages yet, Software Update now prepares the Cybex OS release on its own, on the packages your computer runs now. The newer NixOS packages follow once NixOS has built them.

While newer NixOS packages are only waiting for NixOS, Software Update, Settings and the Control Center now say your system is up to date, with one short line that the packages follow once they are built. There is no warning, update badge or list of package names, because there is nothing for you to do.

On computers that log in automatically after unlocking the disk, a NixOS package update no longer waits forever for the Cybex OS encryption check. That check is part of Cybex OS and is now built on your computer like Cybex OS's other parts.

This is a source update with no new ISO. Installation, boot, physical hardware and staged-updater qualification are separate from source tests and package builds.
