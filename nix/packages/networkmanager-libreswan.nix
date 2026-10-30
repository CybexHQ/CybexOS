{ networkmanager-libreswan, libreswan }:
# Nixpkgs' plugin recipe (1.2.31 on nixos-unstable) points at
# libexec/{pluto,whack}, but its Libreswan 5 package installs libexec/ipsec/*.
# Keep the maintained upstream plugin and correct only these native helper
# paths. Remove this override once Nixpkgs fixes them, after installed VPN
# qualification. It is an expected local build (nix/modules/applications.nix).
networkmanager-libreswan.overrideAttrs (old: {
  doCheck = true;
  postPatch = (old.postPatch or "") + ''
    for helper in pluto whack; do
      test -x "${libreswan}/libexec/ipsec/$helper"
      substituteInPlace src/nm-libreswan-service.c \
        --replace-fail "${libreswan}/libexec/$helper" "${libreswan}/libexec/ipsec/$helper"
    done
  '';
})
