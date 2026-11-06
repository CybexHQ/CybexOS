# Cybex OS 1.0.20

Experimental hardware profiles now cover Framework 13 AMD 7040 and ThinkPad T14 Gen 5 AMD, alongside the existing Dell XPS and HP ZBook targets. Fresh installations select reviewed profiles by exact model identity. Existing machines keep their settings and receive guidance when a profile is available.

The installer and System Check show hardware support status and known limitations. Hardware inventory distinguishes detected profiles from configured settings and reports the running and configured kernel versions separately. A profile match does not mean every device has been physically tested.

Every Cybex OS configuration now requires the unmodified stock Nixpkgs kernel. Updates refuse custom kernels and pending kernel compilation while preserving personal configuration and machine-owned locks. Ordinary packaged external modules, including NVIDIA drivers, remain allowed.

Fresh XPS installations leave the unsupported built-in camera off and recommend a USB webcam. Existing explicit camera settings remain unchanged; camera capture is still unqualified.

This is a source update with no new ISO. Installation, boot, physical hardware and staged-updater qualification are separate from source tests and package/system builds.
