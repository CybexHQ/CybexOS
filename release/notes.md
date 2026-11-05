# Cybex OS 1.0.18

- Cybex OS releases now have two channels. **Stable** gets a release once it has proven itself; **beta** gets new releases first. Turn on **Get beta releases** in Settings → Bar & Control Center → Updates, or run `cybex update channel beta`. Changing it asks for your password and needs no rebuild. NixOS package updates are the same on both channels.
- Leaving beta never downgrades Cybex OS. If you run a newer version than the newest stable release, Software Update says so and offers the next stable release once it passes yours, instead of reporting an error.
- An update prepared from a beta release is set aside when the computer moves to stable, so it is never installed by accident.

This is a source update with no new ISO. Installation, boot and physical hardware qualification are separate from source, build and isolated updater/UI checks.
