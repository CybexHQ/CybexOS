{ config, lib, pkgs, ... }:
let
  cfg = config.cybexos;
  sudo = config.security.sudo;
in {
  config = lib.mkIf cfg.enable {
    # Every installed generation includes the root-owned rule directory. The
    # Settings switch owns only whether its one NOPASSWD rule exists there.
    # sudo skips a missing directory and every name containing a dot, and the
    # last matching rule wins, so the include comes after the wheel rule.
    security.sudo.extraConfig = lib.mkAfter ''
      @includedir /var/lib/cybexos/passwordless-sudo
    '';
    systemd.tmpfiles.rules = [ "d /var/lib/cybexos/passwordless-sudo 0755 root root -" ];
    environment.etc."cybexos/passwordless-sudo.json".text = builtins.toJSON {
      user = cfg.primaryUser;
      available = sudo.enable && builtins.elem "wheel" config.users.users.${cfg.primaryUser}.extraGroups;
      # A personal module may already make every administrator passwordless.
      passwordRequired = sudo.wheelNeedsPassword;
      visudo = "${sudo.package}/bin/visudo";
    };
    environment.systemPackages = [ (pkgs.writeTextDir "share/polkit-1/actions/org.cybexos.passwordless-sudo.policy" ''
      <?xml version="1.0" encoding="UTF-8"?>
      <!DOCTYPE policyconfig PUBLIC "-//freedesktop//DTD PolicyKit Policy Configuration 1.0//EN" "http://www.freedesktop.org/standards/PolicyKit/1/policyconfig.dtd">
      <policyconfig>
        <action id="org.cybexos.passwordless-sudo">
          <description>Turn sudo without password on or off</description>
          <message>Authenticate to change whether sudo asks for your password</message>
          <defaults><allow_any>no</allow_any><allow_inactive>no</allow_inactive><allow_active>auth_admin</allow_active></defaults>
          <annotate key="org.freedesktop.policykit.exec.path">${cfg.updaterPackage}/bin/cybexos-passwordless-sudo</annotate>
        </action>
      </policyconfig>
    '') ];
  };
}
