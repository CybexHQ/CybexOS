# Check the real packaged services and generated LPMd override without starting
# hardware daemons. Targets and D-Bus are isolated from the build host.
{ nixpkgs, pkgs, module, system }:
let
  config = (nixpkgs.lib.nixosSystem {
    inherit system;
    modules = [ module ./machine.nix {
      cybexos.hardware.xps = { enable = true; sku = "0DB9"; camera = false; };
    } ];
  }).config;
  lpmd = nixpkgs.lib.findFirst (p: nixpkgs.lib.getName p == "intel-lpmd") null config.systemd.packages;
  service = config.systemd.services.intel_lpmd;
in pkgs.runCommand "cybexos-xps-power-ordering" {
  nativeBuildInputs = [ pkgs.systemd ];
} ''
  mkdir units
  cp ${lpmd}/lib/systemd/system/intel_lpmd.service units/
  cp ${config.services.power-profiles-daemon.package}/lib/systemd/system/power-profiles-daemon.service units/
  cp ${config.services.upower.package}/etc/systemd/system/upower.service units/
  mkdir units/intel_lpmd.service.d
  cp ${config.systemd.units."intel_lpmd.service".unit}/intel_lpmd.service units/intel_lpmd.service.d/overrides.conf

  for target in basic sysinit shutdown; do
    printf '[Unit]\nDefaultDependencies=no\n' > "units/$target.target"
  done
  cat > units/multi-user.target <<'EOF'
  [Unit]
  Requires=basic.target
  After=basic.target
  EOF
  cat > units/graphical.target <<'EOF'
  [Unit]
  Requires=multi-user.target
  Wants=display-manager.target
  After=multi-user.target display-manager.target
  EOF
  cat > units/display-manager.target <<'EOF'
  [Unit]
  After=multi-user.target
  EOF
  cat > units/dbus.service <<EOF
  [Service]
  ExecStart=${pkgs.coreutils}/bin/true
  EOF
  cat > units/dbus.socket <<'EOF'
  [Socket]
  ListenStream=/run/dbus/system_bus_socket
  EOF

  # Materialize the NixOS activation links, including those of upstream PPD.
  mkdir units/graphical.target.wants
  ln -s ../power-profiles-daemon.service units/graphical.target.wants/
  for target in ${nixpkgs.lib.escapeShellArgs service.wantedBy}; do
    mkdir -p "units/$target.wants"
    ln -s ../intel_lpmd.service "units/$target.wants/"
  done
  # Verification uses the same target ordering rules in either scope. User
  # scope keeps systemd 262's manager scratch directory inside the sandbox;
  # system scope unconditionally tries to create /run/systemd, even with --root.
  export SYSTEMD_UNIT_PATH="$PWD/units"
  export XDG_RUNTIME_DIR="$PWD/runtime"
  mkdir -m 700 "$XDG_RUNTIME_DIR"
  verify() {
    systemd-analyze --user verify --man=no graphical.target
  }
  verify > fixed.log 2>&1 || { cat fixed.log; exit 1; }
  if grep -qi 'ordering cycle' fixed.log; then
    cat fixed.log
    exit 1
  fi

  # Negative control: the old multi-user dependency must reproduce the cycle,
  # so this check cannot silently pass with an incomplete target graph.
  rm units/*.target.wants/intel_lpmd.service
  mkdir -p units/multi-user.target.wants
  ln -s ../intel_lpmd.service units/multi-user.target.wants/
  verify > old.log 2>&1 || true
  grep -i 'ordering cycle' old.log
  touch "$out"
''
