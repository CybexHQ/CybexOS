# Cybex OS 1.0.17

- OpenCode is no longer bundled with the default developer tools. Its broken Nixpkgs 2.2.5 dependency download was blocking system updates. Personal package declarations remain untouched, and NixOS package updates remain enabled.
- When NixOS has not supplied a prebuilt package, Software Update now shows **Waiting for NixOS packages**, names the packages and offers **Check Again**. That explanation survives restarting the desktop. The same held candidate no longer produces a new-update indicator; changed sources and firmware remain discoverable.
- With automatic preparation enabled, package holds are checked again for a new source or personal configuration, or after a day, even when the first attempt was manual. Other failures and personal software changes still require attention.

This is a source update with no new ISO. Installation, boot and physical hardware qualification are separate from source, build and isolated updater/UI checks.
