{ config, options, lib, pkgs, ... }:
let
  cfg = config.cybexos;
  xps = cfg.hardware.xps;
  zbook = cfg.hardware.zbookUltraG1a;
  # XPS 14 DA14260 (0DB9) and XPS 16 DA16260 (0DBA) share their audio, camera
  # and haptics. The XPS 13 DX13260 is 0E53 on Wildcat Lake, 0E54 on Panther Lake.
  xps14or16 = lib.elem xps.sku [ "0DB9" "0DBA" ];
  # Quirks measured on one exact SKU and panel EDID (docs/hardware-compatibility.md).
  xpsPsrOff = xps.sku == "0DB9" && xps.panel == "30e4c607";
  camera = pkgs.callPackage ../packages/ipu7.nix { inherit (config.boot.kernelPackages) kernel kernelModuleMakeFlags; };
  lpmd = pkgs.callPackage ../packages/intel-lpmd.nix {};
  micmuteLed = pkgs.writeShellApplication {
    name = "cybexos-micmute-led";
    runtimeInputs = with pkgs; [ coreutils gawk pulseaudio systemd ];
    text = builtins.readFile ../../hardware/micmute-led;
  };
  relay = config.services.v4l2-relayd.instances.ipu7;
in {
  options.cybexos.hardware = {
    nvidia = lib.mkOption { type = lib.types.bool; default = false; };
    nvidiaOpen = lib.mkOption { type = lib.types.bool; default = true; description = "Use open kernel modules on supported Turing or newer GPUs; choose false for supported older devices"; };
    nvidiaPrime = {
      enable = lib.mkEnableOption "hybrid graphics with explicit PRIME render offload";
      intelBusId = lib.mkOption { type = lib.types.str; default = ""; };
      amdgpuBusId = lib.mkOption { type = lib.types.str; default = ""; };
      nvidiaBusId = lib.mkOption { type = lib.types.str; default = ""; };
    };
    xps = {
      enable = lib.mkEnableOption "matched Dell XPS 2026 hardware";
      sku = lib.mkOption { type = lib.types.str; default = ""; };
      panel = lib.mkOption { type = lib.types.str; default = ""; };
      camera = lib.mkEnableOption "OVTI08F4/8086:b05d IPU7 processed camera";
      lowPower = lib.mkOption { type = lib.types.bool; default = true; description = "Intel LPMd active-idle optimization on the exact matched XPS platform; retains upstream CPU/platform safety checks"; };
      hapticIntensity = lib.mkOption { type = lib.types.enum [ "low" "mid" "high" ]; default = "high"; };
    };
    zbookUltraG1a = {
      enable = lib.mkEnableOption "matched HP ZBook Ultra G1a (board 8D01, AMD Strix Halo)";
      smartPc = lib.mkOption {
        type = lib.types.bool; default = false;
        description = ''
          AMD PMF Smart PC policies from the BIOS. Off by default: after s2idle on
          BIOS 01.05.07 and later the policy engine fails every second
          ("TEE enact cmd failed"), and Linux 7.3 does not restart it on resume.
          The static power slider and power profiles keep working without it.
        '';
      };
    };
  };
  config = lib.mkMerge [ (lib.mkIf cfg.enable (lib.mkMerge [ {
    hardware.enableRedistributableFirmware = lib.mkDefault true;
    # Without regulatory.db cfg80211 stays on the world domain, whatever the
    # access point advertises: 6 GHz and some 5 GHz channels stay passive-only
    # on Wi-Fi 6E/7 radios such as Intel BE211 and MediaTek MT7925.
    hardware.wirelessRegulatoryDatabase = lib.mkDefault true;
    hardware.graphics = { enable = true; enable32Bit = cfg.features.steam; };
    # The matched laptop profile this machine was configured with. cybex doctor
    # compares it with the hardware it runs on (docs/laptop-support.md).
    environment.etc."cybexos/hardware-profile.json".text = builtins.toJSON {
      schema = 1;
      xps = if xps.enable then xps.sku else null;
      zbookUltraG1a = zbook.enable;
    };
    # Laptop drivers light *::micmute from an ALSA capture switch, which the
    # SoundWire and AMD ACP digital microphones of current laptops do not
    # have: PipeWire mutes them in software and the light never changes.
    # Follow the default microphone instead, through logind.
    environment.systemPackages = [ micmuteLed ];
    systemd.user.services.micmute-led = {
      description = "Microphone mute light follows the default microphone";
      wantedBy = [ "hyprland-session.target" ];
      partOf = [ "hyprland-session.target" ];
      after = [ "pipewire-pulse.service" "wireplumber.service" ];
      unitConfig.ConditionPathExistsGlob = "/sys/class/leds/*::micmute";
      serviceConfig = { ExecStart = "${micmuteLed}/bin/cybexos-micmute-led"; Restart = "on-failure"; RestartSec = 2; };
    };
    # The other native KMS drivers start in stage 1 on the medium too
    # (default.nix). Nouveau's firmware would make the medium's initrd 1.4 GB
    # instead of about 110 MB, so only installed machines carry it there.
    boot.initrd.availableKernelModules = lib.optional (!cfg.hardware.nvidia) "nouveau";
    boot.initrd.kernelModules = lib.optionals cfg.hardware.nvidia [
      "nvidia" "nvidia_modeset" "nvidia_drm"
    ];
    services.hardware.bolt.enable = lib.mkDefault true;
  } (lib.mkIf cfg.hardware.nvidia {
    # Selecting NVIDIA is an explicit driver choice, independent of the
    # optional proprietary application group. Its userspace is unfree even
    # when the open kernel module is selected. Permit only these drivers.
    nixpkgs.config = lib.mkIf (options.nixpkgs.config.type.name != "unique") {
      allowUnfreePredicate = lib.mkDefault (package:
        lib.elem (lib.getName package) [ "nvidia-x11" "nvidia-kernel-modules" "nvidia-settings" "nvidia-persistenced" ]);
    };
    services.xserver.videoDrivers = [ "nvidia" ];
    hardware.nvidia = {
      modesetting.enable = true;
      open = cfg.hardware.nvidiaOpen;
      powerManagement.enable = true;
      # Leave package selection to NixOS's branch option. Pinning stable here
      # prevented a machine from selecting legacy_580 for Maxwell/Pascal/Volta.
      branch = lib.mkDefault (if cfg.hardware.nvidiaOpen then "stable" else "legacy_580");
    };
    hardware.nvidia.prime = lib.mkIf cfg.hardware.nvidiaPrime.enable {
      inherit (cfg.hardware.nvidiaPrime) intelBusId amdgpuBusId nvidiaBusId;
      offload = { enable = true; enableOffloadCmd = true; };
    };
    services.switcherooControl.enable = lib.mkDefault cfg.hardware.nvidiaPrime.enable;
    hardware.graphics.extraPackages = [ pkgs.nvidia-vaapi-driver ];
    # NVIDIA's EGL platform libraries, which the NixOS driver module adds for
    # 32-bit graphics (Steam): NixOS prebuilds only the 64-bit ones. They are
    # expected driver builds, like the driver itself (nix/modules/prebuilt.nix).
    cybexos.updates.expectedBuilds = lib.optionals config.hardware.graphics.enable32Bit
      (with pkgs.pkgsi686Linux; [ egl-wayland egl-gbm egl-wayland2 egl-x11 ]);
    environment.sessionVariables = { NVD_BACKEND = "direct"; }
      // lib.optionalAttrs (!cfg.hardware.nvidiaPrime.enable) {
        LIBVA_DRIVER_NAME = "nvidia"; __GLX_VENDOR_LIBRARY_NAME = "nvidia";
      };
  }) (lib.mkIf xps.enable {
    assertions = [
      { assertion = lib.elem xps.sku [ "0DB9" "0DBA" "0E53" "0E54" ]; message = "XPS quirks require the exact supported SKU."; }
      { assertion = xps.camera -> xps14or16; message = "The processed XPS camera stack is reviewed for the XPS 14/16 (0DB9/0DBA) only."; }
    ];
    boot.kernelParams = lib.optional (xps14or16 && lib.hasPrefix "30e4" xps.panel) "xe.enable_dpcd_backlight=1"
      ++ lib.optional xpsPsrOff "xe.enable_psr=0"
      # Stock equivalents of Dell's display quirks for the XPS 13, which are
      # not upstream (docs/laptop-support.md). Panther Lake: Panel
      # Replay and PSR2 stutter and corrupt the panel, so keep PSR1 only.
      # Wildcat Lake: Panel Replay delivers about 40 % of scrolled frames late.
      ++ lib.optionals (xps.sku == "0E54") [ "xe.enable_psr=1" "xe.enable_panel_replay=0" ]
      ++ lib.optional (xps.sku == "0E53") "xe.enable_panel_replay=0"
      # The firmware opts into DMA protection, so the IOMMU is on but maps
      # internal devices 1:1. The XPS 14's DRAM-less SanDisk SN7100S then
      # gets no 64 MiB host memory buffer: unremapped, the NVMe driver can
      # offer it only eight 4 MiB chunks. Translated DMA gives it one segment.
      ++ [ "intel_iommu=on" ];
    # XPS 14/16: intel_cvs claims the GPIO (INTC10BC:01 pin 20) from which the
    # four CS35L57 speaker amplifiers read their speaker ID, and it autoloads
    # first, so every amplifier fails with -EBUSY and no sound card appears.
    # The amplifiers read and release the line while probing; the camera
    # initializer loads CVS explicitly once they have all bound.
    boot.blacklistedKernelModules = lib.optional xps14or16 "intel_cvs";
    # XPS 13 Panther Lake: Linux 7.3 lacks the cs42l43 speaker-ID quirk for
    # 0E54 (7da2aca12375, in 7.4), so both sidecar amplifiers miss their
    # firmware and the speakers are silent. Drive them from the codec's own
    # amplifier until then: audible, with less bass.
    boot.extraModprobeConfig = lib.mkIf (xps.sku == "0E54"
      && lib.versionOlder config.boot.kernelPackages.kernel.version "7.4") ''
      options snd_soc_sof_sdw quirk=1
    '';
    # With PSR off, the driver enables Link Off Between Frames (LOBF) on this
    # panel instead. Its link then drops about every three seconds, and each
    # retrain power-cycles the panel for 1.2 s under the display lock, freezing
    # the whole desktop. Xe has no parameter for LOBF, only this debugfs switch;
    # set it before the display manager's first modeset (docs/hardware-compatibility.md).
    systemd.services.xps-panel-link = lib.mkIf xpsPsrOff {
      description = "Keep the XPS panel link on between frames";
      wantedBy = [ "multi-user.target" ];
      before = [ "display-manager.service" ];
      requires = [ "sys-kernel-debug.mount" ];
      after = [ "sys-kernel-debug.mount" ];
      serviceConfig = { Type = "oneshot"; RemainAfterExit = true; };
      script = ''
        found=0
        for control in /sys/kernel/debug/dri/*/eDP-1/i915_edp_lobf_debug; do
          [ -e "$control" ] || continue
          echo 1 > "$control"
          found=1
        done
        [ "$found" = 1 ] || { echo "The internal panel's LOBF control is missing." >&2; exit 1; }
      '';
    };
    # PPD owns user-selected profiles. Adaptive thermald supplies the separate
    # firmware/DPTF thermal protection; do not run a competing profile manager.
    services.thermald.enable = lib.mkDefault true;
    cybexos.updates.additionalHealthServices = lib.optional config.services.thermald.enable "thermald.service";
    hardware.graphics.extraPackages = with pkgs; [ intel-media-driver vpl-gpu-rt intel-compute-runtime ];
  }) (lib.mkIf (xps.enable && xps14or16) {
    # The speaker voicing was measured on the XPS 14's CS35L57 speakers and is
    # shared with the XPS 16. The XPS 13's cs42l43 speakers have none.
    environment.sessionVariables.CYBEXOS_XPS_2026 = "1";
    environment.etc."cybexos/xps-audio/filter-chain.conf".source = ../../hardware/xps/xps-speaker-filter-chain.conf;
    environment.etc."cybexos/xps-audio/host.conf".source = ../../hardware/xps/xps-speaker-host.conf;
    environment.systemPackages = [ (pkgs.writeShellApplication {
      name = "xps-speaker-tuning";
      runtimeInputs = with pkgs; [ coreutils gnugrep gnused gawk pulseaudio pipewire ];
      text = ''
        export CYBEXOS_LSP_LV2=${pkgs.lsp-plugins}/lib/lv2
        export LV2_PATH=${pkgs.lsp-plugins}/lib/lv2
        exec ${pkgs.bash}/bin/bash ${../../hardware/xps/xps-speaker-tuning} "$@"
      '';
    }) ];
    systemd.user.services.xps-speaker-tuning = {
      wantedBy = [ "hyprland-session.target" ];
      partOf = [ "hyprland-session.target" ];
      after = [ "pipewire.service" "wireplumber.service" ];
      path = with pkgs; [ bash coreutils gnugrep gnused gawk pulseaudio pipewire ];
      environment = { CYBEXOS_LSP_LV2 = "${pkgs.lsp-plugins}/lib/lv2"; LV2_PATH = "${pkgs.lsp-plugins}/lib/lv2"; };
      serviceConfig = {
        ExecStart = "${pkgs.bash}/bin/bash ${../../hardware/xps/xps-speaker-tuning} run";
        ExecStartPost = "${pkgs.bash}/bin/bash ${../../hardware/xps/xps-speaker-tuning} activate";
        ExecStopPost = "${pkgs.bash}/bin/bash ${../../hardware/xps/xps-speaker-tuning} deactivate";
        Restart = "on-failure"; RestartSec = 5;
      };
    };
  }) (lib.mkIf (xps.enable && xps.lowPower && xps.sku != "0E53") {
    # The pinned LPMd carries Intel's Panther Lake policy only; Wildcat Lake
    # (the XPS 13's 0E53) has a policy in later LPMd releases.
    # LPMd follows the PowerProfiles D-Bus API (PPD here, TuneD's bridge
    # before). PPD alone owns EPP/EPB and platform profiles. Upstream's Panther
    # Lake policy keeps LP-mode CPU restriction off in all three profiles and
    # sets the SoC power slider for AC/battery. Neither daemon replaces the other.
    environment.systemPackages = [ lpmd ];
    environment.etc."intel_lpmd".source = "${lpmd}/etc/intel_lpmd";
    users.groups.power = {};
    services.dbus.packages = [ lpmd ];
    # Keep upstream's unit: its virtualization condition, unsupported-platform
    # exit status and restart limits. The alias serves its D-Bus activation.
    systemd.packages = [ lpmd ];
    systemd.services.intel_lpmd = {
      wantedBy = [ "multi-user.target" ];
      aliases = [ "org.freedesktop.intel_lpmd.service" ];
      after = [ "power-profiles-daemon.service" "upower.service" ];
    };
    cybexos.updates.reportedHealthServices = [ "intel_lpmd.service" ];
  }) (lib.mkIf (xps.enable && xps.camera) {
    environment.systemPackages = [ (pkgs.writeShellApplication {
      name = "xps-ipu7-camera-frame-check";
      runtimeInputs = [ pkgs.python3 pkgs.v4l-utils ];
      text = ''
        exec python3 ${../../hardware/xps/camera/xps-ipu7-camera-frame-check} "$@"
      '';
    }) ];
    # Source and kernel identities are a single generation. A failure blocks
    # the new generation; it never mutates the camera stack on the running OS.
    boot.extraModulePackages = [ camera.psys ];
    # CVS must acquire the sensor's USBIO power path before sensor probing.
    # Explicit modprobe from the managed initializer bypasses the blacklist.
    boot.blacklistedKernelModules = [ "ov08x40" ];
    boot.extraModprobeConfig = ''
      softdep ov08x40 pre: intel_cvs
      install intel-ipu7-psys ${pkgs.writeShellScript "ipu7-checked-load" ''
        export PATH=${lib.makeBinPath [ pkgs.python3 pkgs.pahole pkgs.kmod pkgs.zstd pkgs.coreutils ]}
        ${pkgs.python3}/bin/python3 ${../../hardware/xps/camera/xps-ipu7-abi-check} || exit $?
        exec ${pkgs.kmod}/bin/modprobe --ignore-install intel-ipu7-psys "$@"
      ''}
    '';
    # Keep the vendor file names: extraRules lands in 99-local.rules, after
    # 73-seat-late.rules has already queued the desktop uaccess ACL.
    services.udev.packages = [ (pkgs.runCommand "xps-ipu7-udev-rules" {} ''
      install -Dm444 ${../../hardware/xps/camera/71-xps-ipu7-hide-isys.rules} $out/lib/udev/rules.d/71-xps-ipu7-hide-isys.rules
      install -Dm444 ${../../hardware/xps/camera/90-xps-ipu7-psys.rules} $out/lib/udev/rules.d/90-xps-ipu7-psys.rules
    '') ];
    # The relay's GStreamer source is part of this camera's own stack.
    cybexos.updates.expectedBuilds = [ camera.sensor ];
    services.v4l2-relayd.instances.ipu7 = {
      enable = true; cardLabel = "Hardware ISP Camera";
      extraPackages = [ camera.sensor ];
      input = {
        pipeline = "icamerasrc device-name=ov08x40-uf sharpness=80 ev=-1 saturation=10 ! videoflip method=rotate-180";
        format = "NV12"; width = 1920; height = 1080;
      };
      output.format = "NV12";
    };
    # The relay can remain idle until an application opens its loopback node.
    # Active relay status alone therefore cannot certify the stock/private ABI.
    # Check the booted kernel independently, including after a trial boot.
    systemd.services.xps-ipu7-abi = {
      description = "Validate the booted XPS IPU7 private kernel ABI";
      wantedBy = [ "multi-user.target" ];
      path = [ pkgs.python3 pkgs.pahole pkgs.kmod pkgs.zstd pkgs.coreutils ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${pkgs.python3}/bin/python3 ${../../hardware/xps/camera/xps-ipu7-abi-check}";
      };
    };
    systemd.services.v4l2-relayd-ipu7 = {
      requires = [ "xps-ipu7-abi.service" "xps-ipu7-camera-init.service" ];
      after = [ "xps-ipu7-abi.service" "xps-ipu7-camera-init.service" ];
      partOf = [ "xps-ipu7-camera-init.service" ];
      # Keep NixOS's dynamic, exclusive-capable loopback lifecycle and plugin
      # paths. Avoid holding a producer sample across splash/capture changes.
      script = lib.mkForce ''
        pipeline=${lib.escapeShellArg ("appsrc name=appsrc caps=video/x-raw,format=${relay.input.format},width=${toString relay.input.width},height=${toString relay.input.height},framerate=${toString relay.input.framerate}/1 ! videoconvert"
          + lib.optionalString (relay.input.format != relay.output.format) " ! video/x-raw,format=${relay.output.format} ! queue")}
        exec ${pkgs.v4l2-relayd}/bin/v4l2-relayd \
          -i ${lib.escapeShellArg relay.input.pipeline} \
          -o "$pipeline ! v4l2sink name=v4l2sink device=$(cat "$V4L2_DEVICE_FILE") enable-last-sample=false"
      '';
      # Each start (boot, resume) recreates the exclusive-caps loopback node,
      # which only advertises capture once the relay attaches. Make the
      # logged-in session rediscover it; no session is a harmless no-op.
      serviceConfig.ExecStartPost = "-${pkgs.writeShellScript "xps-ipu7-refresh-wireplumber" ''
        ${pkgs.coreutils}/bin/sleep 2
        exec ${pkgs.systemd}/bin/systemctl --user --machine=${lib.escapeShellArg cfg.primaryUser}@.host try-restart wireplumber.service
      ''}";
    };
    systemd.services.xps-ipu7-camera-init = {
      description = "Initialize the matched XPS processed camera in CVS-first order";
      wantedBy = [ "multi-user.target" ];
      requires = [ "xps-ipu7-abi.service" ];
      after = [ "xps-ipu7-abi.service" ];
      before = [ "v4l2-relayd-ipu7.service" ];
      path = with pkgs; [ coreutils gnugrep kmod systemd ];
      # It waits up to 60 s for the speaker amplifiers before loading CVS.
      serviceConfig = { Type = "oneshot"; RemainAfterExit = true; TimeoutStartSec = 120; };
      script = builtins.readFile ../../hardware/xps/camera/xps-ipu7-camera-init;
    };
    systemd.services.xps-ipu7-camera-sleep = {
      description = "Quiesce the XPS camera before sleep and restore it after wake";
      wantedBy = [ "sleep.target" ];
      before = [ "sleep.target" ];
      unitConfig.StopWhenUnneeded = true;
      serviceConfig = {
        Type = "oneshot"; RemainAfterExit = true;
        # Cancel a pending restore first so repeated or suspend-then-hibernate
        # sleeps stay idempotent. Kernel IPU7 modules are never cycled here.
        ExecStart = "${pkgs.systemd}/bin/systemctl stop xps-ipu7-camera-resume.service v4l2-relayd-ipu7.service";
        ExecStop = [
          "-${pkgs.systemd}/bin/systemctl reset-failed xps-ipu7-camera-resume.service"
          "${pkgs.systemd}/bin/systemctl --no-block restart xps-ipu7-camera-resume.service"
        ];
      };
    };
    systemd.services.xps-ipu7-camera-resume = {
      description = "Restore the XPS processed camera after sleep";
      path = [ pkgs.coreutils pkgs.systemd ];
      serviceConfig = { Type = "oneshot"; TimeoutStartSec = 90; };
      script = ''
        sleep 2
        systemctl restart xps-ipu7-camera-init.service
        systemctl reset-failed v4l2-relayd-ipu7.service
        systemctl start v4l2-relayd-ipu7.service
      '';
    };
    cybexos.updates.reportedHealthServices = [ "xps-ipu7-camera-init.service" ];
    systemd.tmpfiles.rules = [ "d /run/camera 0750 root video -" ];
  }) (lib.mkIf zbook.enable {
    # Display, audio (ALC245 with four CS35L54 amplifiers), microphones (ACP
    # PDM), camera (AMD ISP4), MT7925 Wi-Fi/Bluetooth, the Synaptics reader
    # and touchpad all run on the stock kernel and firmware; see
    # docs/laptop-support.md for the BIOS settings they depend on.
    boot.extraModprobeConfig = lib.mkIf (!zbook.smartPc) ''
      options amd_pmf smart_pc_support=0
    '';
  }) ]))
  (lib.mkIf ((cfg.enable && xps.enable) || cfg.installationMedium) {
    # The generic live image needs the same controller wake/click handling as
    # the installed XPS. Gate it with the installer's exact hardware matcher;
    # never apply this model's HID reports or power quirks to other laptops.
    environment.etc."cybexos/xps-haptic.conf".text =
      "INTENSITY=${toString { low = 10; mid = 50; high = 100; }.${xps.hapticIntensity}}\n";
    systemd.services.xps-haptic-touchpad = {
      wantedBy = [ "multi-user.target" ];
      # Only the Synaptics haptic touchpad is driven; without one the daemon
      # would keep its I2C controller awake while waiting for it.
      unitConfig.ConditionPathExistsGlob = "/sys/bus/i2c/devices/i2c-VEN_06CB:*";
      path = [ pkgs.python3 ];
      serviceConfig = {
        ExecCondition = lib.optional cfg.installationMedium (pkgs.writeShellScript "match-xps-touchpad" ''
          export PYTHONPATH=${cfg.updaterPackage}/lib
          exec ${pkgs.python3}/bin/python3 -c 'from cybexos.hardware import detect; raise SystemExit(0 if detect()["xps"] else 1)'
        '');
        ExecStart = "${pkgs.python3}/bin/python3 ${../../hardware/xps/xps-haptic-touchpad}";
        Restart = "on-failure"; RestartSec = 5;
      };
    };
  }) ];
}
