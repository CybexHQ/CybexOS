# Cybex OS 1.0.31

Updates no longer fail on computers with ChatGPT while NixOS is missing packages ChatGPT needs. The newest NixOS packages include a codex and a tectonic that NixOS couldn't build, and the update check let them through because they sat underneath the ChatGPT download, so the computer tried to build them itself and failed. The check now waits for NixOS to build them: Software Update says your system is up to date, installs new Cybex OS releases on your current NixOS packages in the meantime, and takes the newer NixOS packages once NixOS has built them.

If an update already failed this way, this release can't install through it yet, because the update check on your computer is still the old one. Run `cybex update stage cybexos` once to prepare this release on its own, then install it from Software Update; later updates handle this by themselves.

This is a source update with no new ISO. Installation, boot, physical hardware and staged-updater qualification are separate from source tests and package builds.
