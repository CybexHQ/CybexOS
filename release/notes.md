# Cybex OS 1.0.23

Dell XPS models that use Intel LPMd now start their power-management services in a consistent order. This removes the dependency loop that made systemd drop a service job during startup or shutdown.

This is a source update with no new ISO. Installation, boot, physical hardware and staged-updater qualification are separate from source tests and package builds.
