{ config, lib, pkgs, ... }:
let
  guard = pkgs.callPackage ../packages/lid-guard.nix {};
in {
  config = lib.mkIf config.cybexos.enable {
    # Docking is defined by connected DRM outputs, not logind's enabled/DPMS
    # test or a dock switch that can remain present after its display is gone.
    # The guard inhibits only handle-lid-switch, never sleep or idle suspend.
    services.logind.settings.Login = {
      HandleLidSwitch = lib.mkDefault "suspend";
      HandleLidSwitchExternalPower = lib.mkDefault "suspend";
      HandleLidSwitchDocked = lib.mkDefault "suspend";
    };
    systemd.services.cybexos-lid-guard = {
      description = "Keep external-display lid policy independent of DPMS";
      wantedBy = [ "multi-user.target" "systemd-logind.service" ];
      after = [ "systemd-logind.service" ];
      before = [ "display-manager.service" ];
      partOf = [ "systemd-logind.service" ];
      serviceConfig = {
        Type = "notify";
        # Keep the inhibitor alive while an update restarts the service, even
        # with the lid closed and the external display already in DPMS off.
        FileDescriptorStoreMax = 1;
        FileDescriptorStorePreserve = "restart";
        ExecStart = "${guard}/bin/cybexos-lid-guard";
        Restart = "on-failure";
        RestartSec = 1;
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        RestrictAddressFamilies = [ "AF_UNIX" "AF_NETLINK" ];
      };
    };
    cybexos.updates.additionalHealthServices = [ "cybexos-lid-guard.service" ];
  };
}
