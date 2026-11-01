# Sudo without password

Open **Settings → Security → Sudo** and turn on **Sudo without password**.
Approve the administrator prompt. From then on `sudo` in a terminal runs
without asking for your password, including `sudo -n` in scripts and agents.
Turn it off the same way to make sudo ask again.

The switch is off on a fresh installation. It takes effect at once, with no
rebuild or restart, and it remembers its state after a restart and across
system updates and rollbacks. While it is on, the row says so in a warning:
any program running as you can become administrator without asking. System
prompts (Polkit: Software, updates, this switch itself) still ask for the
password, and signing in, the lock screen and disk unlock are unchanged.

Every installed generation ends `/etc/sudoers` with
`@includedir /var/lib/cybexos/passwordless-sudo`, after the wheel rule, so a
rule there wins. That directory is root-owned and empty until the switch adds
one file, `rule`, mode 0440:

```
cybex ALL=(ALL:ALL) NOPASSWD: SETENV: ALL
```

It names the machine's primary user only (`cybexos.primaryUser`), never the
whole wheel group, and keeps the `SETENV` tag the wheel rule has. sudo skips a
missing directory and every file whose name contains a dot, which keeps the
helper's lock and temporary files out of the policy. The helper checks the new
rule with the system's `visudo` before it takes effect, so a rule sudo could
not parse never locks you out.

The setting uses a narrow Polkit helper, `cybexos-passwordless-sudo`, that
accepts only enable, disable and read-only status. It does not rebuild the
system, store a password or edit personal NixOS modules. Its declared facts are
in `/etc/cybexos/passwordless-sudo.json`.

Personal NixOS modules in `/etc/nixos/local` still decide. If one sets
`security.sudo.wheelNeedsPassword = false`, every administrator is already
passwordless: the switch shows on and **Managed in /etc/nixos/local** instead of
offering a choice it cannot make. If one disables sudo or takes the primary
user out of `wheel`, the switch reports unavailable; turning an existing rule
off still works. The installation ISO has no sudo at all.

Tests: `tests/nixos/test_passwordless_sudo.py` (the helper and the Settings
bridge), `checks.x86_64-linux.passwordless-sudo` (`nix/tests/passwordless-sudo.nix`:
Polkit, the helper and real sudo in a booted system, across a restart) and the
installed-desktop authorization step of `scripts/qualify-installations`, which
answers the real Polkit prompt.
