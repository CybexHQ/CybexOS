{ python3, writeScriptBin }:
let
  python = python3.withPackages (p: [ p.dbus-python p.pygobject3 p.pyudev ]);
in writeScriptBin "cybexos-lid-guard" ''
  #!${python}/bin/python3
  ${builtins.readFile ../../desktop/power/lid_guard.py}
''
