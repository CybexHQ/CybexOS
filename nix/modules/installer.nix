{ config, options, lib, pkgs, modulesPath, ... }:
# The installation ISO boots straight into the installer: no desktop session,
# display manager or live account. tty1 shows cybexos-installer, a Slint kiosk
# drawn with the software renderer directly to KMS/DRM; it runs unprivileged
# in a logind seat session and owns no state. cybexos-installerd (root) keeps
# the draft and drives the one disk-writing worker, cybexos-install, whose
# protocol and checks are shared with the terminal and automated installers.
let
  cfg = config.cybexos.installer;
  installer = pkgs.callPackage ../packages/installer.nix { source = ../..; };
  updater = installer.passthru.updater;
  payload = cfg.payload;
  # The medium carries the free part of the default desktop as an offline
  # payload, so installation copies most store paths instead of downloading
  # them. The payload's initrd is per machine and is rebuilt during install;
  # unfree groups (proprietary, Steam) and NVIDIA drivers still download.
  payloadContents = lib.optionals (payload != null) (with payload.config; [
    system.path
    system.build.etc
    system.modulesTree
    boot.kernelPackages.kernel
    systemd.package
    system.build.installBootLoader
    # The option's apply merges every firmware package into one tree.
    hardware.firmware
  ]);
  reservedNames = lib.optionals (payload != null) (lib.subtractLists [ payload.config.cybexos.primaryUser ]
    (lib.unique (builtins.attrNames payload.config.users.users ++ builtins.attrNames payload.config.users.groups)));
  text = lib.getExe' updater "cybexos-install";
  plymouth = lib.getExe' config.boot.plymouth.package "plymouth";
  # After the screen ends: a clean exit (a keyboard change) or 75 (the text
  # installer already has tty1) is not a failure. Neither is one while another
  # VT is active: the screen cannot hold the display behind the recovery
  # shell. Three failures within a minute ask the state service for the text
  # installer, as the screen's menu does; it refuses while installing.
  screenFailed = pkgs.writeShellScript "cybexos-installer-screen-failed" ''
    if [ "$SERVICE_RESULT" = success ] || [ "$EXIT_STATUS" = 75 ]; then
      exit 0
    fi
    if [ "$(${pkgs.coreutils}/bin/cat /sys/class/tty/tty0/active 2>/dev/null)" != tty1 ]; then
      exit 0
    fi
    state=/run/cybexos-installer/screen-failures
    now=$(${pkgs.coreutils}/bin/date +%s)
    recent=$({ ${pkgs.coreutils}/bin/cat "$state" 2>/dev/null; echo "$now"; } | ${pkgs.gawk}/bin/awk -v now="$now" 'now - $1 < 60')
    printf '%s\n' "$recent" > "$state"
    count=$(printf '%s\n' "$recent" | ${pkgs.coreutils}/bin/wc -l)
    if [ "$count" -ge 3 ]; then
      ${pkgs.coreutils}/bin/rm -f "$state"
      echo "The installer screen failed $count times within a minute ($SERVICE_RESULT); asking for the text installer."
      ${lib.getExe' installer "cybexos-installerd"} --client --request '{"action":"text-installer"}' --timeout 5 >/dev/null || true
    fi
  '';
  # A change event on the DRM devices once a driver's framebuffer console is added.
  probeDisplays = systemd: ''
    ACTION=="add", SUBSYSTEM=="graphics", KERNEL=="fb[0-9]*", RUN+="${systemd}/bin/udevadm trigger --action=change --subsystem-match=drm --property-match=DEVTYPE=drm_minor"
  '';
in {
  imports = [ (modulesPath + "/installer/cd-dvd/installation-cd-minimal.nix") ./iso-boot.nix ];

  options.cybexos.installer.payload = lib.mkOption {
    type = lib.types.nullOr lib.types.raw;
    default = null;
    internal = true;
    description = "An evaluated default Cybex OS system whose store paths the medium carries for installation.";
  };

  config = {
    cybexos.installationMedium = true;

    environment.etc."cybexos/installer".text = "fresh-install-only\n";
    # Interpolation retains the store dependency. toString would leave a dangling
    # path on the live medium and make the offline source unavailable.
    environment.etc."cybexos/installer-source".text = "${../..}";
    environment.etc."cybexos/installer-ui".source = installer;
    environment.etc."cybexos/installer-defaults.json".text = builtins.toJSON
      (lib.mapAttrs (_: option: option.default) options.cybexos.features);
    environment.etc."cybexos/installer-region.json".text = builtins.toJSON {
      timezone = config.time.timeZone;
      locale = config.i18n.defaultLocale;
      keyboard = config.console.keyMap;
      desktopKeyboard = config.services.xserver.xkb.layout;
    };
    environment.etc."cybexos/installer-layout.json".text = builtins.toJSON config.cybexos.installation;
    environment.etc."cybexos/installer-reserved-names.json".text = builtins.toJSON reservedNames;
    environment.systemPackages = [ installer updater pkgs.nixos-install-tools pkgs.pciutils ];
    isoImage.storeContents = payloadContents;

    # ── no live desktop or account ──────────────────────────────────────────
    # Physical access already means control of the disks being installed; the
    # medium still exposes no remote login and no passwordless sudo account.
    users.users.nixos.enable = false;
    security.sudo.enable = lib.mkForce false;
    services.openssh.enable = lib.mkForce false;
    services.getty.autologinUser = lib.mkForce "root";
    services.getty.helpLine = lib.mkForce ''
      Cybex OS installer recovery shell. Alt+F1 returns to the installer screen.
      nmtui configures the network. The installation log is /run/cybexos-installer.log.
      For the text installer, choose "Use the text installer" in the screen's
      menu, or start the ISO's text-mode entry.
    '';
    documentation.enable = lib.mkForce false;
    documentation.nixos.enable = lib.mkForce false;
    documentation.man.enable = lib.mkForce false;
    documentation.info.enable = lib.mkForce false;
    documentation.doc.enable = lib.mkForce false;
    system.installer.channel.enable = false;
    networking.hostName = lib.mkForce "cybexos-installer";
    services.logind.settings.Login = {
      IdleAction = "ignore";
      HandleLidSwitch = "ignore";
      HandleLidSwitchExternalPower = "ignore";
      HandleLidSwitchDocked = "ignore";
    };

    # ── the installer screen and its state service ──────────────────────────
    users.groups.cybexos-installer = { };
    users.users.cybexos-installer = {
      isSystemUser = true;
      group = "cybexos-installer";
      description = "Cybex OS installer screen";
      extraGroups = [ "video" "input" ];
    };
    systemd.tmpfiles.rules = [ "d /run/cybexos-installer 0750 root cybexos-installer -" ];
    # tty1 belongs to the installer screen (or the text installer). NixOS
    # otherwise wants autovt@tty1 (getty@tty1) at boot; a Wants-only conflict
    # in the boot transaction makes systemd drop one side arbitrarily, before
    # any kernel command line condition is checked. logind still starts
    # autovt@ttyN for the other VTs, including the tty2 recovery shell.
    systemd.targets.getty.wants = lib.mkForce [ ];
    security.pam.services.cybexos-installer.text = ''
      auth    required pam_unix.so nullok
      account required pam_unix.so
      session required pam_unix.so
      session required pam_env.so conffile=/etc/pam/environment readenv=0
      session required ${config.systemd.package}/lib/security/pam_systemd.so
    '';

    systemd.services.cybexos-installerd = {
      description = "Cybex OS installer state service";
      wantedBy = [ "multi-user.target" ];
      after = [ "systemd-tmpfiles-setup.service" "NetworkManager.service" ];
      wants = [ "NetworkManager.service" ];
      unitConfig.ConditionKernelCommandLine = "!cybexos.text";
      serviceConfig = {
        ExecStart = lib.getExe' installer "cybexos-installerd";
        Restart = "on-failure";
        RestartSec = "1s";
        # The worker must outlive a daemon restart; it is cancelled explicitly
        # before the text installer takes over.
        KillMode = "process";
        # An out-of-memory build fails through the worker and is shown; the
        # default policy would stop the whole service and reset the screen.
        OOMPolicy = "continue";
        StandardOutput = "journal";
        StandardError = "journal";
      };
    };

    # The boot splash and its progress bar stay until the screen has drawn,
    # as with a display manager. Just before the screen starts, the splash
    # completes its bar and releases the display, its last frame still shown.
    # The screen reports its first frame (Type=notify), then plymouth-quit ends
    # Plymouth without clearing it. Plymouth is driven from its own units:
    # each command of the screen's unit hangs up and resets tty1.
    systemd.services.cybexos-installer-splash = {
      description = "Hand the boot splash's display to the Cybex OS installer screen";
      after = [ "cybexos-installerd.service" "systemd-user-sessions.service" "systemd-logind.service" ];
      unitConfig.ConditionKernelCommandLine = "!cybexos.text";
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = [
          # Native display drivers can still be binding when boot finishes.
          "-${config.systemd.package}/bin/udevadm settle --timeout=15"
          # The bar fills in a quarter of a second (desktop/plymouth/cybexos.script).
          "-${plymouth} update --status=cybexos-installer-ready"
          "${pkgs.coreutils}/bin/sleep 0.3"
          "-${plymouth} deactivate"
        ];
      };
    };
    systemd.services.plymouth-quit = {
      after = [ "cybexos-installer-ui.service" ];
      serviceConfig.ExecStart = [ "" "-${plymouth} quit --retain-splash" ];
    };

    systemd.services.cybexos-installer-ui = {
      description = "Cybex OS installer screen";
      wantedBy = [ "multi-user.target" ];
      wants = [ "cybexos-installerd.service" "cybexos-installer-splash.service" ];
      after = [ "cybexos-installerd.service" "systemd-user-sessions.service" "systemd-logind.service" "cybexos-installer-splash.service" ];
      unitConfig = {
        ConditionKernelCommandLine = "!cybexos.text";
        # A keyboard change restarts the screen; it must never give up.
        StartLimitIntervalSec = 0;
      };
      serviceConfig = {
        # Started once its first frame is on the screen.
        Type = "notify";
        User = "cybexos-installer";
        PAMName = "cybexos-installer";
        TTYPath = "/dev/tty1";
        TTYReset = true;
        TTYVHangup = true;
        TTYVTDisallocate = true;
        StandardInput = "tty-fail";
        StandardOutput = "journal";
        StandardError = "journal";
        UtmpIdentifier = "tty1";
        UtmpMode = "user";
        IgnoreSIGPIPE = false;
        ExecStart = lib.getExe installer;
        EnvironmentFile = "-/run/cybexos-installer/keyboard.env";
        Environment = [ "XDG_SESSION_TYPE=wayland" "XDG_SESSION_CLASS=user" ];
        Restart = "always";
        RestartSec = "300ms";
        # 75: no usable display; the text installer has taken tty1.
        RestartPreventExitStatus = 75;
        # A screen that keeps failing must not leave a black display.
        ExecStopPost = "+${screenFailed}";
      };
    };

    # The text installer: the boot menu's text entry (cybexos.text), or the
    # screen's menu, or automatically when no display device works. At boot
    # the kernel command line alone selects either side; no boot-time unit
    # conflicts with another (see getty.wants above).
    systemd.services.cybexos-installer-text = {
      description = "Cybex OS text installer";
      wantedBy = [ "multi-user.target" ];
      after = [ "NetworkManager.service" "plymouth-quit-wait.service" ];
      unitConfig.ConditionKernelCommandLine = "cybexos.text";
      environment.TERM = "linux";
      serviceConfig = {
        ExecStart = "${text} --terminal";
        TTYPath = "/dev/tty1";
        TTYReset = true;
        TTYVHangup = true;
        StandardInput = "tty-force";
        StandardOutput = "tty";
        StandardError = "tty";
        Restart = "no";
      };
    };
    # The screen's menu starts the text installer without the kernel flag.
    systemd.services.cybexos-installer-text-switch = {
      description = "Switch tty1 to the Cybex OS text installer";
      conflicts = [ "getty@tty1.service" "cybexos-installer-ui.service" "cybexos-installerd.service" ];
      after = [ "cybexos-installer-ui.service" "cybexos-installerd.service" ];
      environment.TERM = "linux";
      serviceConfig = {
        ExecStart = "${text} --terminal";
        TTYPath = "/dev/tty1";
        TTYReset = true;
        TTYVHangup = true;
        StandardInput = "tty-force";
        StandardOutput = "tty";
        StandardError = "tty";
        Restart = "no";
      };
    };

    # ── hardware and boot ───────────────────────────────────────────────────
    # The medium boots with systemd stage 1 like installed machines: NixOS
    # removed the scripted initrd. Stage 1 waits for the volume label
    # (/dev/disk/by-label/CYBEXOS_INSTALL), which USB and optical media carry.
    # iVentoy 1.0.41 boots its own init first: it unpacks its tools under
    # /ventoy and this initrd into the same root, then patches the scripted
    # /init to run its NixOS hook before the root mount. The hook brings up the
    # wired NIC and attaches the ISO as /dev/nbd0 (its nbd-client carries
    # systemd's keep-alive mark). systemd's binary /init cannot be patched, so
    # this unit runs the same hook, only when iVentoy injected it, with
    # iVentoy's bundled DHCP client on PATH. Network boots may take longer to
    # find the label than local media.
    boot.initrd.systemd.services.cybexos-network-medium = {
      description = "Attach the iVentoy network installation medium";
      wantedBy = [ "initrd.target" ];
      before = [ "initrd-root-device.target" "sysroot-iso.mount" ];
      after = [ "systemd-udevd.service" "systemd-udev-trigger.service" "systemd-modules-load.service" ];
      unitConfig = {
        DefaultDependencies = false;
        ConditionPathExists = "/ventoy/hook/nixos/ventoy_disk.sh";
      };
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        Environment = "PATH=/ventoy/tools:/ventoy/busybox:/bin:/sbin";
        ExecStart = "/ventoy/busybox/sh /ventoy/hook/nixos/ventoy_disk.sh";
        StandardOutput = "journal+console";
        TimeoutStartSec = "5min";
      };
    };
    # The iVentoy hook attached its ISO in about 13 s on real hardware, even
    # after its DHCP client failed; two minutes leaves room for slow links.
    boot.initrd.systemd.settings.Manager.DefaultDeviceTimeoutSec = "2min";
    # A medium that never appears (a stick written by copying files, a hub or
    # dock that drops it, a failing stick) ends stage 1 in emergency mode.
    # Explain that instead of a splash that eases on, then a bare shell.
    boot.initrd.systemd.contents."/etc/cybexos/medium-missing.txt".text = ''

      Cybex OS could not find its installation medium.

      The installer started, but the USB stick or network image labelled
      CYBEXOS_INSTALL did not appear within two minutes.

      - Write the image again as a raw disk image: balenaEtcher, Fedora Media
        Writer, dd, or Rufus in "DD Image" mode. Copying files onto a stick
        (Rufus "ISO Image" mode) cannot work: the image holds a file larger
        than 4 GB.
      - Plug the stick into the computer itself, not a hub, dock or monitor,
        and try another USB port or another stick of 8 GB or more.
      - For a network boot, check the cable and that the boot server is on.

      Turn the computer off, then fix the medium and start again.

    '';
    boot.initrd.systemd.services.cybexos-medium-missing = {
      description = "Explain a missing Cybex OS installation medium";
      wantedBy = [ "emergency.target" ];
      before = [ "emergency.service" ];
      unitConfig = {
        DefaultDependencies = false;
        ConditionPathExists = "!/dev/disk/by-label/CYBEXOS_INSTALL";
      };
      serviceConfig = {
        Type = "oneshot";
        # Wait for the splash to end, so emergency mode's own quit finds
        # nothing left to report on the console.
        ExecStartPre = "-/bin/plymouth --wait quit";
        ExecStart = "/bin/cat /etc/cybexos/medium-missing.txt";
        # Plain text on the console: through the journal, every line would
        # carry a kernel timestamp and wrap.
        StandardOutput = "tty";
        TTYPath = "/dev/console";
      };
    };
    # A network-medium hook needs the wired NIC in stage 1; the ordinary CD
    # profile only carries storage drivers there. In particular, the X1 Pro's
    # RTL8125 (10ec:8125) uses r8169.
    boot.initrd.availableKernelModules = [
      "af_packet" "nbd"
      "r8169" "r8152" "igc" "igb" "e1000e" "e1000" "ixgbe" "i40e" "ice"
      "tg3" "bnx2" "bnx2x" "atlantic" "mlx4_en" "mlx5_core"
      "asix" "ax88179_178a" "cdc_ether" "cdc_ncm" "rndis_host"
    ];
    # Keep serial diagnostics, but send /dev/console prompts to the local screen.
    # The splash waits for the native display driver, which stage 1 carries for
    # AMD, Intel and virtual GPUs (default.nix). It is not drawn on the firmware
    # framebuffer first: on the Minisforum X1 Pro 370 (Radeon 890M) that
    # framebuffer showed garbled text and no splash. Other GPUs (NVIDIA, until
    # nouveau loads in stage 2) get the firmware framebuffer after Plymouth's
    # eight-second device timeout.
    # The Thunderbolt driver loads in stage 2. By default it resets the host
    # router and tears down the tunnels the firmware made, which disconnects
    # whatever the medium boots through a dock or display: the USB stick, or
    # the network adapter of a network boot. The medium keeps those tunnels,
    # as Linux did before 6.9; installed systems keep the reset.
    boot.kernelParams = [ "console=ttyS0,115200n8" "console=tty0" "plymouth.ignore-serial-consoles"
      "thunderbolt.host_reset=0" ];
    # The splash's variant with the medium's boot progress (nix/packages/plymouth.nix).
    boot.plymouth.theme = "cybexos-installer";
    # When a native driver loads, Plymouth opens its new device at once. Not
    # being its DRM master, it gets a read-only probe, and before the kernel's
    # first probe every output reads as disconnected; Plymouth gives up on the
    # device until a change event. The driver adds its framebuffer console after
    # that probe, so report a change on the DRM devices then, in either stage.
    services.udev.extraRules = probeDisplays config.systemd.package;
    boot.initrd.services.udev.rules = probeDisplays config.boot.initrd.systemd.package;
    # The medium supports ZFS but never boots from a pool: take NixOS's
    # forthcoming default rather than forcibly importing a root pool.
    boot.zfs.forceImportRoot = false;
    # The screen draws with the CPU through any KMS driver (amdgpu, i915/xe,
    # nouveau, virtio) or the firmware framebuffer (simpledrm with nomodeset),
    # so the medium needs no GPU userspace and no separate NVIDIA kernel. The
    # installed system still selects its own NVIDIA driver.
    system.requiredKernelConfig = with config.lib.kernelConfig; [
      (isYes "DRM_SIMPLEDRM")
    ];
    isoImage = {
      volumeID = "CYBEXOS_INSTALL";
      makeEfiBootable = true;
      makeUsbBootable = true;
      prependToMenuLabel = "Install ";
      appendToMenuLabel = "";
      grubTheme = config.cybexos.bootTheme;
      # The legacy BIOS notice (nix/modules/iso-boot.nix).
      splashImage = "${config.cybexos.bootTheme}/bios.png";
      efiSplashImage = ../../desktop/boot/splash.png;
    };
    # The first final release's requested media name; metadata stays SemVer.
    image.baseName = lib.mkForce (if config.cybexos.release.version == "1.0.0"
      then "cybexos-1.0" else "cybexos-${config.cybexos.release.version}-${pkgs.stdenv.hostPlatform.system}");
    system.stateVersion = "26.05";
  };
}
